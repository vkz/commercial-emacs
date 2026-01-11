(in-package #:elisp)

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; SBCL traps some IEEE floating-point exceptions by default (notably NaN
  ;; comparisons).  Emacs Lisp expects IEEE behavior without trapping, so
  ;; disable FP traps during clemacs bring-up.
  #+sbcl
  (ignore-errors
    (sb-int:set-floating-point-modes :traps nil)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Emacs Lisp uses a variety of DECLARE properties for edebug/indentation,
  ;; docstrings, and metadata.  When we translate ELisp to CL forms, preserve
  ;; these declarations as no-ops to keep compiler output quiet while loading
  ;; more of lisp/.
	  (cl:declaim
	   (cl:declaration
	    advertised-calling-convention
	    compiler-macro
	    completion
	    debug
	    doc-string
	    indent
	    important-return-value
	    interactive-only
	    obsolete
	    pure
	    side-effect-free)))

(cl:defvar *elisp-readtable* nil)

(cl:deftype function (&rest _args)
  "Type alias for ELISP::FUNCTION (maps to CL:FUNCTION).

Ignore argument/result type restrictions for now; these are used for bring-up
compiler declarations and should not fail compilation."
  (declare (cl:ignore _args))
  'cl:function)

(cl:defun native-comp-function-p (_function)
  "Return non-nil when FUNCTION has an associated native-compiled version.

Native compilation is intentionally disabled in this fork, so this always
returns nil."
  nil)

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Define numeric-only `+' / `-' early without redefinition warnings when the
  ;; system is loaded repeatedly (e.g. during core rebuilds).
  (unless (cl:fboundp '+)
    (setf (cl:symbol-function '+)
          (lambda (&rest args)
            (if (null args)
                0
                (cl:apply #'cl:+ args))))
    (setf (cl:documentation '+ 'cl:function)
          "Temporary numeric-only ELisp `+'."))
  (unless (cl:fboundp '-)
    (setf (cl:symbol-function '-)
          (lambda (x &rest more)
            (if (null more)
                (cl:- x)
                (cl:reduce #'cl:- more :initial-value x))))
    (setf (cl:documentation '- 'cl:function)
          "Temporary numeric-only ELisp `-'.")))

(defconstant +raw-byte-base+ #x3fff00)
(defconstant +raw-byte-max+ #x3fffff)
;; Represent raw-byte multibyte chars (#x3fff00..#x3fffff) in CL strings using a
;; private-use range. This keeps "multibyte strings are CL strings" workable
;; while still exposing the correct ELisp character codes via AREF and FORMAT.
(defconstant +raw-byte-private-base+ #xE000)
(defconstant +raw-byte-private-max+ (cl:+ +raw-byte-private-base+ 255))

(deftype unibyte-string ()
  '(array (unsigned-byte 8) (*)))

(cl:deftype string ()
  "Type alias for ELISP::STRING (includes unibyte + multibyte strings)."
  '(or cl:string unibyte-string))

(deftype list-of (&optional (element-type t))
  "Accept `cl-lib' style (list-of TYPE) declarations.

This is primarily a compilation aid for ELisp that uses `cl-lib' macros which
emit type declarations like (list-of symbol). SBCL's type system can't express
\"list of X\" precisely without runtime checks, so we conservatively treat it
as just `list`."
  (declare (cl:ignore element-type))
  'list)

(cl:defun unibyte-string-p (x)
  (typep x 'unibyte-string))

(cl:defun stringp (x)
  "ELisp-ish STRINGP.

In Emacs, unibyte strings and multibyte strings are distinct. In clemacs,
unibyte strings are `(simple-array (unsigned-byte 8) (*))`, while multibyte
strings are CL strings."
  (or (cl:stringp x) (unibyte-string-p x)))

(cl:defun string (&rest characters)
  "Bring-up subset of ELisp `string'."
  (let ((out (cl:make-string (length characters))))
    (loop for ch in characters
          for i from 0 do
            (cond
             ((integerp ch)
              (setf (cl:aref out i) (%elisp-code->char ch)))
             ((cl:characterp ch)
              (setf (cl:aref out i) ch))
             (t
              (if (fboundp 'signal)
                  (signal 'wrong-type-argument (list 'characterp ch))
                  (cl:error "ELISP:STRING expects characters, got: ~S" ch)))))
    out))

(cl:defun car (x)
  "ELisp-ish CAR.

Return the car of X.  Signal `wrong-type-argument' when X is not a list."
  (cond
   ((null x) nil)
   ((consp x) (cl:car x))
   (t
    (if (fboundp 'signal)
        (signal 'wrong-type-argument (list 'listp x))
        (cl:error "ELISP:CAR expected list, got: ~S" x)))))

(cl:defun cdr (x)
  "ELisp-ish CDR.

Return the cdr of X.  Signal `wrong-type-argument' when X is not a list."
  (cond
   ((null x) nil)
   ((consp x) (cl:cdr x))
   (t
    (if (fboundp 'signal)
        (signal 'wrong-type-argument (list 'listp x))
        (cl:error "ELISP:CDR expected list, got: ~S" x)))))

(cl:defun (setf car) (newcar cell)
  "ELisp-ish (SETF CAR)."
  (unless (consp cell)
    (if (fboundp 'signal)
        (signal 'wrong-type-argument (list 'consp cell))
        (cl:error "ELISP:(SETF CAR) expected cons, got: ~S" cell)))
  (setf (cl:car cell) newcar)
  newcar)

(cl:defun (setf cdr) (newcdr cell)
  "ELisp-ish (SETF CDR)."
  (unless (consp cell)
    (if (fboundp 'signal)
        (signal 'wrong-type-argument (list 'consp cell))
        (cl:error "ELISP:(SETF CDR) expected cons, got: ~S" cell)))
  (setf (cl:cdr cell) newcdr)
  newcdr)

(cl:defmacro %define-cxxr (name letters)
  (unless (and (cl:stringp letters)
               (cl:<= 2 (cl:length letters) 4)
               (cl:every (lambda (ch) (or (char= ch #\a) (char= ch #\d)))
                         letters))
    (cl:error "Bad cXXr spec: ~S ~S" name letters))
  (let ((form 'x))
    (loop for ch across (reverse letters) do
      (setf form (list (if (char= ch #\a) 'car 'cdr) form)))
    `(cl:defun ,name (x)
       (declare (compiler-macro internal--compiler-macro-cXXr))
       ,form)))

(%define-cxxr caar "aa")
(%define-cxxr cadr "ad")
(%define-cxxr cdar "da")
(%define-cxxr cddr "dd")
(%define-cxxr caaar "aaa")
(%define-cxxr caadr "aad")
(%define-cxxr cadar "ada")
(%define-cxxr caddr "add")
(%define-cxxr cdaar "daa")
(%define-cxxr cdadr "dad")
(%define-cxxr cddar "dda")
(%define-cxxr cdddr "ddd")
(%define-cxxr caaaar "aaaa")
(%define-cxxr caaadr "aaad")
(%define-cxxr caadar "aada")
(%define-cxxr caaddr "aadd")
(%define-cxxr cadaar "adaa")
(%define-cxxr cadadr "adad")
(%define-cxxr caddar "adda")
(%define-cxxr cadddr "addd")
(%define-cxxr cdaaar "daaa")
(%define-cxxr cdaadr "daad")
(%define-cxxr cdadar "dada")
(%define-cxxr cdaddr "dadd")
(%define-cxxr cddaar "ddaa")
(%define-cxxr cddadr "ddad")
(%define-cxxr cdddar "ddda")
(%define-cxxr cddddr "dddd")

(cl:defmacro %define-setf-cxxr (name letters)
  (unless (and (cl:stringp letters)
               (cl:<= 2 (cl:length letters) 4)
               (cl:every (lambda (ch) (or (char= ch #\a) (char= ch #\d)))
                         letters))
    (cl:error "Bad (setf cXXr) spec: ~S ~S" name letters))
  (let* ((len (cl:length letters))
         (ops (reverse letters))
         (prefix (subseq ops 0 (cl:1- len)))
         (last (char ops (cl:1- len)))
         (cell (cl:gensym "CELL")))
    `(cl:defun (setf ,name) (new x)
       (let ((,cell x))
         ,@(loop for ch across prefix collect
             `(setf ,cell (,(if (char= ch #\a) 'car 'cdr) ,cell)))
         (setf (,(if (char= last #\a) 'car 'cdr) ,cell) new)
         new))))

(%define-setf-cxxr caar "aa")
(%define-setf-cxxr cadr "ad")
(%define-setf-cxxr cdar "da")
(%define-setf-cxxr cddr "dd")
(%define-setf-cxxr caaar "aaa")
(%define-setf-cxxr caadr "aad")
(%define-setf-cxxr cadar "ada")
(%define-setf-cxxr caddr "add")
(%define-setf-cxxr cdaar "daa")
(%define-setf-cxxr cdadr "dad")
(%define-setf-cxxr cddar "dda")
(%define-setf-cxxr cdddr "ddd")
(%define-setf-cxxr caaaar "aaaa")
(%define-setf-cxxr caaadr "aaad")
(%define-setf-cxxr caadar "aada")
(%define-setf-cxxr caaddr "aadd")
(%define-setf-cxxr cadaar "adaa")
(%define-setf-cxxr cadadr "adad")
(%define-setf-cxxr caddar "adda")
(%define-setf-cxxr cadddr "addd")
(%define-setf-cxxr cdaaar "daaa")
(%define-setf-cxxr cdaadr "daad")
(%define-setf-cxxr cdadar "dada")
(%define-setf-cxxr cdaddr "dadd")
(%define-setf-cxxr cddaar "ddaa")
(%define-setf-cxxr cddadr "ddad")
(%define-setf-cxxr cdddar "ddda")
(%define-setf-cxxr cddddr "dddd")

(cl:defun vectorp (x)
  "Bring-up subset of ELisp `vectorp'.

In ELisp, strings are arrays but *not* vectors."
  (and (cl:vectorp x) (not (stringp x)) t))

(cl:defun sequencep (x)
  "Bring-up subset of ELisp `sequencep'.

In Emacs, a sequence is a list or an array (including strings)."
  (and (or (listp x) (vectorp x) (stringp x)) t))

(cl:defun multibyte-string-p (s)
  "Bring-up subset of the C primitive `multibyte-string-p'."
  (and (stringp s) (not (unibyte-string-p s)) t))

(cl:defun %raw-byte-char-code-p (code)
  (and (integerp code) (<= +raw-byte-base+ code +raw-byte-max+)))

(cl:defun %raw-byte-private-char-p (ch)
  (and (cl:characterp ch)
       (let ((cc (char-code ch)))
         (<= +raw-byte-private-base+ cc +raw-byte-private-max+))))

(cl:defun %raw-byte-code->private-char (code)
  (unless (%raw-byte-char-code-p code)
    (error "ELISP: not a raw-byte char code: ~S" code))
  (let* ((byte (- code +raw-byte-base+))
         (cc (+ +raw-byte-private-base+ byte))
         (ch (code-char cc)))
    (or ch (error "ELISP: cannot represent raw-byte ~S as CL character" code))))

(cl:defun %private-char->raw-byte-code (ch)
  (unless (%raw-byte-private-char-p ch)
    (error "ELISP: not a raw-byte private char: ~S" ch))
  (+ +raw-byte-base+ (- (char-code ch) +raw-byte-private-base+)))

(cl:defun %elisp-char-code (ch)
  "Return the ELisp character code integer for CL character CH."
  (if (%raw-byte-private-char-p ch)
      (%private-char->raw-byte-code ch)
      (char-code ch)))

(cl:defun %elisp-code->char (code)
  "Return a CL character for ELisp CODE (including raw-byte codes)."
  (cond
   ((%raw-byte-char-code-p code)
    (%raw-byte-code->private-char code))
   ((cl:characterp code) code)
   ((and (integerp code) (<= 0 code))
    (or (code-char code)
        (error "ELISP: invalid character code: ~S" code)))
   (t
    (error "ELISP: expected character code, got: ~S" code))))

(cl:defun %make-unibyte-string (len &key (initial-element 0))
  (let ((b (typecase initial-element
             (integer initial-element)
             (character (char-code initial-element))
             (t (error "ELISP: bad unibyte init element: ~S" initial-element)))))
    (unless (and (integerp b) (<= 0 b 255))
      (error "ELISP: unibyte init out of range: ~S" initial-element))
    (make-array len :element-type '(unsigned-byte 8) :initial-element b)))

(cl:defun %unibyte->cl-string (bytes)
  (unless (unibyte-string-p bytes)
    (error "ELISP: expected unibyte string, got: ~S" (type-of bytes)))
  (let ((out (cl:make-string (length bytes))))
    (dotimes (i (length bytes))
      (setf (char out i) (code-char (aref bytes i))))
    out))

(cl:defun %elisp-string->cl-string (s)
  "Return a CL string for S (unibyte or multibyte).

For unibyte strings, this is a lossy view for bytes >= 128 if later treated as
Unicode; use `string-to-multibyte' to preserve raw-byte semantics."
  (cond
   ((cl:stringp s) s)
   ((unibyte-string-p s) (%unibyte->cl-string s))
   (t (error "ELISP: expected string, got: ~S" (type-of s)))))

(cl:defun string-to-multibyte (s)
  "Bring-up subset of ELisp `string-to-multibyte'."
  (unless (stringp s)
    (error "ELISP:STRING-TO-MULTIBYTE expects a string, got: ~S" s))
  (cond
   ((unibyte-string-p s)
    (let ((out (cl:make-string (length s))))
      (dotimes (i (length s))
        (let ((b (aref s i)))
          (setf (char out i)
                (if (< b 128)
                    (code-char b)
                    (%raw-byte-code->private-char (+ +raw-byte-base+ b))))))
      out))
   (t s)))

(cl:defun string-to-unibyte (s)
  "Bring-up subset of ELisp `string-to-unibyte'."
  (unless (stringp s)
    (error "ELISP:STRING-TO-UNIBYTE expects a string, got: ~S" s))
  (cond
   ((unibyte-string-p s) s)
   (t
    (let* ((n (length s))
           (out (make-array n :element-type '(unsigned-byte 8))))
      (dotimes (i n)
        (let ((ch (char s i)))
          (setf (aref out i)
                (cond
                 ((%raw-byte-private-char-p ch)
                  (- (char-code ch) +raw-byte-private-base+))
                 ((<= (char-code ch) 255) (char-code ch))
                 (t
                  (error "ELISP:STRING-TO-UNIBYTE cannot encode char: ~S" ch))))))
      out))))

(defstruct text-prop-interval
  (start 0 :type integer)
  (end 0 :type integer)
  (plist nil))

(defstruct elisp-struct-literal
  "A reader/printer roundtrippable representation of Emacs `#s(...)' literals."
  (name nil :type symbol)
  (fields nil))

(cl:defvar *string-text-properties*
  (cl:make-hash-table :test 'eq))

(cl:defun %string-text-properties (string)
  (gethash string *string-text-properties*))

(cl:defun %set-string-text-properties (string intervals)
  (setf (gethash string *string-text-properties*) intervals)
  string)

(cl:defun %clear-string-text-properties (string)
  (remhash string *string-text-properties*)
  string)

(defconstant +char-alt+ #x0400000)
(defconstant +char-super+ #x0800000)
(defconstant +char-hyper+ #x1000000)
(defconstant +char-shift+ #x2000000)
(defconstant +char-ctl+ #x4000000)
(defconstant +char-meta+ #x8000000)

(cl:defun %controlify-ascii (code)
  (cond
   ((or (<= (char-code #\A) code (char-code #\Z))
        (<= (char-code #\a) code (char-code #\z))
        (<= (char-code #\@) code (char-code #\_)))
    (logand code #x1f))
   (t nil)))

(cl:defun %read-elisp-escape-code (stream first)
  (labels ((read-hex ()
             (let ((digits nil))
               (loop for ch = (peek-char nil stream nil nil t)
                     while (and ch (digit-char-p ch 16)) do
                       (push (read-char stream nil nil t) digits))
               (unless digits
                 (cl:error "Missing hex digits in ?\\x escape"))
               (parse-integer (coerce (nreverse digits) 'cl:string) :radix 16)))
           (read-octal (first-digit)
             (let ((digits (list first-digit)))
               (loop repeat 2
                     for ch = (peek-char nil stream nil nil t)
                     while (and ch (digit-char-p ch 8)) do
                       (push (read-char stream nil nil t) digits))
               (parse-integer (coerce (nreverse digits) 'cl:string) :radix 8))))
    (case first
      (#\n (char-code #\Newline))
      (#\t (char-code #\Tab))
      (#\r (char-code #\Return))
      (#\s (char-code #\Space))
      (#\b 8)
      (#\d 127)
      (#\f 12)
      (#\a 7)
      (#\e 27)
      (#\\ (char-code #\\))
      (#\" (char-code #\"))
      (#\^
       (let ((next (read-char stream nil nil t)))
         (when (null next)
           (cl:error "EOF in ?\\^ escape"))
         (cond
          ((char= next #\?) 127)
          (t
           (let* ((code (char-code next))
                  (ctl (%controlify-ascii code)))
             (or ctl (logand code #x1f)))))))
      (#\x (read-hex))
      (otherwise
       (cond
        ((digit-char-p first 8)
         (read-octal first))
        (t
         (char-code first)))))))

(cl:defun %read-elisp-char-literal (stream)
  (let ((c (read-char stream nil nil t)))
    (when (null c)
      (cl:error "EOF after ?"))
    (if (not (char= c #\\))
        (char-code c)
        (let ((bits 0)
              (ctlp nil))
          (labels ((add-mod (m)
                     (case m
                       (#\A (incf bits +char-alt+))
                       (#\H (incf bits +char-hyper+))
                       (#\M (incf bits +char-meta+))
                       (#\s (incf bits +char-super+))
                       (#\S (incf bits +char-shift+))
                       (#\C (setf ctlp t))
                       (otherwise (cl:error "Unknown char modifier: ~S" m))))
                   (finish (code)
                     (let ((ctl-code (and ctlp (%controlify-ascii code))))
                       (cond
                        ((and ctlp (= code 0))
                         (+ bits +char-ctl+))
                        (ctl-code
                         (+ bits ctl-code))
                        (ctlp
                         (+ bits +char-ctl+ code))
                        (t
                         (+ bits code)))))
                   (read-base-code ()
                     (let ((ch (read-char stream nil nil t)))
                       (when (null ch)
                         (cl:error "EOF in ?\\ escape"))
                       (if (char= ch #\\)
                           (let ((e (read-char stream nil nil t)))
                             (when (null e)
                               (cl:error "EOF in ?\\ escape"))
                             (%read-elisp-escape-code stream e))
                           (char-code ch)))))
            ;; Parse a possibly-modified char like: ?\C-\M-a or ?\A-\0.
            (loop
              for ch = (read-char stream nil nil t) do
                (when (null ch)
                  (cl:error "EOF in ?\\ escape"))
                (let ((dash (peek-char nil stream nil nil t)))
                  (cond
                   ((and dash (char= dash #\-) (find ch "ACHMsSC" :test #'char=))
                    (read-char stream nil nil t) ; consume '-'
                    (add-mod ch)
                    (let ((next (peek-char nil stream nil nil t)))
                      (when (null next)
                        (cl:error "EOF in ?\\ escape"))
                      (if (char= next #\\)
                          (read-char stream nil nil t) ; consume '\' and loop
                          (return (finish (read-base-code))))))
                   (t
                    (return (finish (%read-elisp-escape-code stream ch))))))))))))

(cl:defun %elisp-rewrite (form)
  (labels ((rw (x)
             (cond
              ((atom x) x)
              ;; Do not rewrite under QUOTE.
              ;; Avoid LIST/LENGTH on dotted pairs (e.g. alists like (quote . "...")).
              ((and (consp x) (eq (car x) 'quote) (consp (cdr x)) (null (cddr x)))
               x)
              ;; ELisp IF allows multiple else forms; CL:IF does not.
              ;; Guard against non-expression lists like (IF INIT) in LET
              ;; bindings when a variable name happens to be CL:IF.
              ((and (consp x) (eq (car x) 'cl:if) (consp (cdr x)) (consp (cddr x)))
               (destructuring-bind (op test then &rest else) x
                 (declare (cl:ignore op))
                 (cond
                  ((null else) (list 'cl:if (rw test) (rw then) nil))
                  ((null (cdr else)) (list 'cl:if (rw test) (rw then) (rw (car else))))
                  (t (list 'cl:if (rw test) (rw then) (cons 'progn (mapcar #'rw else)))))))
              ;; Prefer an ELisp-aware HANDLER-BIND shim so handlers receive
              ;; ELisp-style error data (SYMBOL . DATA), rather than CL
              ;; condition objects.
              ((and (consp x) (eq (car x) 'cl:handler-bind))
               (destructuring-bind (op bindings &rest body) x
                 (declare (cl:ignore op))
                 (cons 'elisp::handler-bind
                       (cons (mapcar #'rw bindings)
                             (mapcar #'rw body)))))
              ;; General cons rewrite: preserve dotted lists.
              (t (cons (rw (car x)) (rw (cdr x)))))))
    (rw form)))

(cl:defun %ensure-elisp-readtable ()
  (or *elisp-readtable*
      (let ((rt (copy-readtable nil)))
        ;; Emacs Lisp backquote/unquote are not reader macros in the CL sense:
        ;; they read into explicit forms using the symbols `\, and \,@.
        ;; This is important because ELisp code expects to see those symbols
        ;; (e.g. backquote.el and pcase patterns).
        (let ((bq (cl:intern "`" (find-package "ELISP")))
              (uq (cl:intern "," (find-package "ELISP")))
              (sp (cl:intern ",@" (find-package "ELISP"))))
          (set-macro-character
           #\'
           (lambda (stream char)
             (declare (cl:ignore char))
             (let ((next (peek-char t stream nil nil t)))
               (cond
                ((and next (char= next #\.))
                 (let* ((dots
                          (with-output-to-string (out)
                            (loop for ch = (peek-char nil stream nil nil t)
                                  while (and ch (char= ch #\.))
                                  do (write-char (read-char stream nil nil t) out))))
                        (sym (cl:intern dots (find-package "ELISP"))))
                   (list 'quote sym)))
                (t
                 (list 'quote (cl:read stream t nil t))))))
           nil
           rt)
          (set-macro-character
           #\`
           (lambda (stream char)
             (declare (cl:ignore char))
             (list bq (cl:read stream t nil t)))
           nil
           rt)
          (set-macro-character
           #\,
           (lambda (stream char)
             (declare (cl:ignore char))
             (let ((next (peek-char nil stream nil nil t)))
               (cond
                ((and next (char= next #\@))
                 (read-char stream nil nil t)
                 (list sp (cl:read stream t nil t)))
                (t
                 (list uq (cl:read stream t nil t))))))
           nil
           rt))
        ;; Emacs Lisp treats `|' as an ordinary symbol constituent (e.g. rx DSL
        ;; uses (| ...)). In CL, `|' is a symbol-escape delimiter, so override
        ;; it so the ELisp reader can consume upstream forms unchanged.
        (set-syntax-from-char #\| #\A rt)
        ;; Emacs Lisp supports `#s(NAME ...)` object literals (primarily from
        ;; cl-defstruct and printer roundtripping). In CL, `#s` reads a struct
        ;; instance, which breaks on unknown structure types while loading
        ;; upstream ELisp tests.
        ;;
        ;; For bring-up, we treat most literals as opaque self-evaluating
        ;; objects with a stable printed representation, but we special-case
        ;; a few core runtime literals that upstream tests rely on, like
        ;; `#s(hash-table ...)`.
        (flet ((read-struct-literal (stream subchar arg)
                 (declare (cl:ignore subchar arg))
                 (let ((form (cl:read stream t nil t)))
                   (unless (and (consp form) (symbolp (car form)))
                     (cl:error "ELISP: invalid #s literal: ~S" form))
                   (let* ((name (car form))
                          (fields (cdr form)))
                     (labels ((plist-get* (plist key)
                                (loop for (k v) on plist by #'cddr
                                      when (eq k key) do (return v)
                                      finally (return :missing)))
                              (even-plist-p (plist)
                                (loop for xs = plist then (cddr xs)
                                      while (consp xs) do
                                        (unless (consp (cdr xs))
                                          (return nil))
                                      finally (return (null xs)))))
                       (cond
                        ;; Emacs prints hash-tables readably as:
                        ;;   #s(hash-table test equal data (k1 v1 k2 v2))
                        ;; Parse the common subset we need for upstream tests.
                        ((and (eq name 'hash-table) (even-plist-p fields))
                         (let* ((test (plist-get* fields 'test))
                                (data (plist-get* fields 'data))
                                (test*
                                  (cond
                                   ((or (eq test :missing) (null test)) 'eql)
                                   ((memq test '(eq eql equal equalp)) test)
                                   (t 'eql)))
                                (ht (cl:make-hash-table :test test*)))
                           (when (and (not (eq data :missing)) (consp data))
                             (unless (even-plist-p data)
                               (cl:error "ELISP: invalid #s(hash-table ...) data: ~S" data))
                             (loop for (k v) on data by #'cddr do
                               (setf (gethash k ht) v)))
                           ht))
                        (t
                         (make-elisp-struct-literal :name name :fields fields))))))))
          (set-dispatch-macro-character #\# #\s #'read-struct-literal rt)
          (set-dispatch-macro-character #\# #\S #'read-struct-literal rt))
        (set-macro-character
         #\"
         (lambda (stream char)
           (declare (cl:ignore char))
           ;; Build an Emacs-style string. Default is unibyte; encountering any
           ;; non-ASCII literal or Unicode escape upgrades to multibyte.
           (let ((mode :unibyte)
                 (ub (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))
                 (codes (make-array 0 :element-type 'integer :adjustable t :fill-pointer 0)))
             (labels ((ensure-multibyte ()
                        (when (eq mode :unibyte)
                          (setf mode :multibyte)
                          (dotimes (i (length ub))
                            (let ((b (aref ub i)))
                              (vector-push-extend (if (< b 128) b (+ +raw-byte-base+ b)) codes)))
                          (setf ub nil)))
                      (push-byte (b)
                        (unless (and (integerp b) (<= 0 b 255))
                          (cl:error "Bad byte in string escape: ~S" b))
                        (if (eq mode :unibyte)
                            (vector-push-extend b ub)
                            (vector-push-extend (if (< b 128) b (+ +raw-byte-base+ b)) codes)))
                      (push-char (ch)
                        (let ((cc (char-code ch)))
                          (cond
                           ((and (eq mode :unibyte) (< cc 128))
                            (push-byte cc))
                           (t
                            (ensure-multibyte)
                            (vector-push-extend cc codes)))))
                      (read-hex ()
                        (let ((digits nil))
                          (loop for ch = (peek-char nil stream nil nil t)
                                while (and ch (digit-char-p ch 16)) do
                                  (push (read-char stream nil nil t) digits))
                          (unless digits
                            (cl:error "Missing hex digits in \\x escape"))
                          (parse-integer (coerce (nreverse digits) 'cl:string) :radix 16)))
                      (read-fixed-hex (n)
                        (let ((digits (cl:make-string n)))
                          (dotimes (i n)
                            (let ((ch (read-char stream nil nil t)))
                              (when (null ch)
                                (cl:error "EOF in Unicode escape"))
                              (unless (digit-char-p ch 16)
                                (cl:error "Bad hex digit in Unicode escape: ~S" ch))
                              (setf (char digits i) ch)))
                          (parse-integer digits :radix 16)))
                      (read-octal (first-digit)
                        (let ((digits (list first-digit)))
                          (loop repeat 2
                                for ch = (peek-char nil stream nil nil t)
                                while (and ch (digit-char-p ch 8)) do
                                  (push (read-char stream nil nil t) digits))
                          (parse-integer (coerce (nreverse digits) 'cl:string) :radix 8)))
                      (finish ()
                        (if (eq mode :unibyte)
                            (let ((out (%make-unibyte-string (length ub))))
                              (replace out ub)
                              out)
                            (let ((out (cl:make-string (length codes))))
                              (dotimes (i (length codes))
                                (setf (char out i) (%elisp-code->char (aref codes i))))
                              out))))
               (loop
                 for ch = (read-char stream nil nil t) do
                   (when (null ch)
                     (cl:error "EOF while reading string"))
                   (cond
                    ((char= ch #\")
                     (return (finish)))
                    ((char= ch #\\)
                     (let ((e (read-char stream nil nil t)))
                       (when (null e)
                         (cl:error "EOF in string escape"))
                       (case e
                         (#\n (push-byte (char-code #\Newline)))
                         (#\t (push-byte (char-code #\Tab)))
                         (#\r (push-byte (char-code #\Return)))
                         (#\s (push-byte (char-code #\Space)))
                         (#\b (push-byte 8))
                         (#\d (push-byte 127))
                         (#\f (push-byte 12))
                         (#\a (push-byte 7))
                         (#\e (push-byte 27))
                         (#\C
                          ;; Emacs-style control escapes inside strings, e.g. "\C-x".
                          ;; This is essential for shipped keymaps that use strings
                          ;; like "\C-x" and "\C-g" in `define-key'.
                          (let ((dash (peek-char nil stream nil nil t)))
                            (when (and dash (char= dash #\-))
                              (read-char stream nil nil t)))
                          (let* ((base0 (read-char stream nil nil t)))
                            (when (null base0)
                              (cl:error "EOF in \\C- string escape"))
                            (let* ((base-code
                                     (if (char= base0 #\\)
                                         (let ((e2 (read-char stream nil nil t)))
                                           (when (null e2)
                                             (cl:error "EOF in \\C- string escape"))
                                           (%read-elisp-escape-code stream e2))
                                         (char-code base0)))
                                   (ctl-code
                                     (if (= base-code (char-code #\?))
                                         127
                                       (cl:logand base-code #x1f))))
                              (push-byte ctl-code))))
                         (#\^
                          (let ((next (read-char stream nil nil t)))
                            (when (null next)
                              (cl:error "EOF in \\^ string escape"))
                            (cond
                             ((char= next #\?) (push-byte 127))
                             (t
                              (let* ((code (char-code next))
                                     (ctl (%controlify-ascii code)))
                                (push-byte (or ctl (cl:logand code #x1f))))))))
                         (#\\ (push-byte (char-code #\\)))
                         (#\" (push-byte (char-code #\")))
                         (#\Newline nil) ; line continuation
                         (#\x
                          (let ((v (read-hex)))
                            (if (<= v 255)
                                (push-byte v)
                                (progn
                                  (ensure-multibyte)
                                  (vector-push-extend v codes)))))
                         (#\u
                          (ensure-multibyte)
                          (vector-push-extend (read-fixed-hex 4) codes))
                         (#\U
                          (ensure-multibyte)
                          (vector-push-extend (read-fixed-hex 8) codes))
                         (#\N
                          (let ((open (read-char stream nil nil t)))
                            (unless (and open (char= open #\{))
                              (cl:error "Bad \\N escape (expected {)"))
                            (let ((chars nil))
                              (loop for c = (read-char stream nil nil t) do
                                (when (null c)
                                  (cl:error "EOF in \\N{...} escape"))
                                (when (char= c #\})
                                  (return))
                                (push c chars))
                              (let* ((raw (coerce (nreverse chars) 'cl:string))
                                     (uplusp
                                       (and (>= (length raw) 3)
                                            (char= (char raw 0) #\U)
                                            (char= (char raw 1) #\+)))
                                     (ch
                                       (cond
                                        (uplusp
                                         (let ((cp (parse-integer raw :start 2 :radix 16)))
                                           (or (code-char cp)
                                               (cl:error "Bad \\N{U+...} codepoint: ~S" raw))))
                                        #+sbcl
                                        (t
                                         (let* ((norm
                                                  (string-upcase
                                                   (substitute #\_ #\Space raw)))
                                                (c0 (sb-unicode::name-char norm)))
                                           (or c0
                                               (cl:error "Unknown \\N name: ~S" raw))))
                                        #-sbcl
                                        (t
                                         (cl:error "\\N{...} escapes require SBCL for now: ~S" raw)))))
                                (push-char ch)))))
                         (otherwise
                          (cond
                           ((digit-char-p e 8)
                            (let ((v (read-octal e)))
                              (if (<= v 255)
                                  (push-byte v)
                                  (progn
                                    (ensure-multibyte)
                                    (vector-push-extend v codes)))))
                           (t
                            ;; Unknown escapes yield the escaped character.
                            (push-char e)))))))
                    (t
                     (push-char ch)))))))
         nil
         rt)
        (set-dispatch-macro-character
         #\#
         #\'
         (lambda (stream sub-char arg)
           (declare (cl:ignore sub-char arg))
           (list (cl:intern "FUNCTION" (find-package "ELISP"))
                 (cl:read stream t nil t)))
         rt)
        (set-dispatch-macro-character
         #\#
         #\(
         (lambda (stream sub-char arg)
           (declare (cl:ignore sub-char arg))
           ;; In Emacs Lisp, #("foo" 0 3 (a b)) is a string with text properties,
           ;; not a vector. Vectors are read via [...].
           (let* ((items (read-delimited-list #\) stream t))
                  (base (first items))
                  (rest (rest items)))
             (unless (stringp base)
               (cl:error "#(...) expects a string first element, got: ~S" base))
             (when (and rest (not (zerop (mod (length rest) 3))))
               (cl:error "#(...) property syntax expects triples: START END PLIST; got: ~S" items))
             (let ((s (copy-seq base))
                   (intervals nil))
               (loop for (start end plist) on rest by #'cdddr do
                 (unless (and (integerp start) (integerp end) (<= 0 start) (<= start end))
                   (cl:error "#(...) bad text property range: ~S ~S" start end))
                 (unless (or (null plist) (listp plist))
                   (cl:error "#(...) bad text property plist: ~S" plist))
                 (push (make-text-prop-interval :start start :end end :plist plist) intervals))
               (%clear-string-text-properties s)
               (when intervals
                 (%set-string-text-properties s (nreverse intervals)))
               s)))
         rt)
        (set-macro-character
         #\[
         (lambda (stream char)
           (declare (cl:ignore char))
           (coerce (read-delimited-list #\] stream t) 'vector))
         nil
         rt)
        (set-macro-character
         #\]
         (lambda (stream char)
           (declare (cl:ignore stream char))
           (cl:error "unexpected ]"))
         nil
         rt)
        (set-macro-character
         #\?
         (lambda (stream char)
           (declare (cl:ignore char))
           (%read-elisp-char-literal stream))
         nil
         rt)
        (setf *elisp-readtable* rt))))

(cl:defun %sanitize-elisp-source/colon-tokens (s)
  "Return a sanitized CL string and a list of inserted positions.

This is a compatibility hack for reading upstream ELisp with CL's reader.

In Emacs Lisp, `:' is just a symbol constituent.  In CL reader syntax, `:'
introduces either a keyword (e.g. `:foo') or package syntax (e.g. `foo:bar').
That makes upstream ELisp forms like `(: ...)' (rx) and symbols like
`http://example.com' signal reader/package errors.

We rewrite colons that would be interpreted as CL package syntax into literal
colons by escaping them (\\:).

We currently preserve:
- leading keyword syntax (`:foo')
- dispatch syntax (`#:' for uninterned symbols)
- a small allowlist of CL package prefixes that appear in `clemacs/ported/`
  (e.g. `cl:foo`, `sb-mop:bar`)."
  (unless (cl:stringp s)
    (cl:error "ELISP: expected CL string, got: ~S" (cl:type-of s)))
  (let* ((len (length s))
         (insertions nil))
    (labels ((delim-p (ch)
               (or (null ch)
                   (cl:member ch '(#\Space #\Tab #\Newline #\Return
                                   #\( #\) #\[ #\] #\" #\' #\` #\, #\;))))
             (%allowed-package-prefix-p (token-start colon-index)
               (and token-start
                    (cl:< token-start colon-index)
                    (cl:member (string-upcase (subseq s token-start colon-index))
                               '("CL" "SB-MOP")
                               :test #'cl:string=)))
             (%scan-elisp-char-literal-end (start)
               "Given START at a '?' character, return the end index (inclusive).

	This is used only to keep the sanitizer's string/comment state machine aligned
	with Emacs Lisp, where `?` introduces a character literal token.  In
	particular, we must not treat `?\\\"` as starting a string."
               (let ((i (1+ start)))
                 (when (>= i len)
                   (return-from %scan-elisp-char-literal-end start))
                 (let ((ch (char s i)))
                   ;; Simple char literal: ?a, ?" etc.
                   (unless (char= ch #\\)
                     (return-from %scan-elisp-char-literal-end i))

                   ;; Escaped char literal and/or modifiers: ?\C-a, ?\^?, ?\xNN, ...
                   (incf i) ; consume '\'
                   (when (>= i len)
                     (return-from %scan-elisp-char-literal-end (1- i)))

                   (labels ((peek () (and (cl:< i len) (char s i)))
                            (consume () (prog1 (peek) (incf i)))
                            (hex-digit-p (c) (and c (digit-char-p c 16)))
                            (oct-digit-p (c) (and c (digit-char-p c 8)))
                            (consume-fixed-hex (n)
                              (dotimes (_ n)
                                (when (cl:< i len) (incf i))))
                            (consume-hex-1+ ()
                              (when (hex-digit-p (peek)) (incf i))
                              (loop while (hex-digit-p (peek)) do (incf i)))
                            (consume-octal-1+ ()
                              (when (oct-digit-p (peek)) (incf i))
                              (loop repeat 2 while (oct-digit-p (peek)) do (incf i)))
                            (consume-escape ()
                              (let ((e (consume)))
                                (when (null e) (return-from consume-escape))
                                (case e
                                  ((#\n #\t #\r #\s #\b #\f #\a #\e #\\ #\") nil)
                                  (#\^ (when (cl:< i len) (incf i)))
                                  (#\x (consume-hex-1+))
                                  (#\u (consume-fixed-hex 4))
                                  (#\U (consume-fixed-hex 8))
                                  (otherwise
                                   (when (digit-char-p e 8)
                                     (consume-octal-1+)))))))
                     ;; Modifier loop: \C- ... possibly repeated (sometimes with
                     ;; an extra '\' between modifiers).
                     (loop
                       (let* ((m (peek))
                              (dash (and (cl:< (1+ i) len) (char s (1+ i)))))
                         (if (and m dash (char= dash #\-) (find m "ACHMsSC" :test #'char=))
                             (progn
                               (incf i 2) ; consume "<mod>-"
                               (when (and (cl:< i len) (char= (peek) #\\))
                                 (incf i)) ; consume '\' and continue modifiers
                               (when (>= i len)
                                 (return-from %scan-elisp-char-literal-end (1- i))))
                           (return))))

                     ;; Base character: either an escape or a single char.
                     (when (>= i len)
                       (return-from %scan-elisp-char-literal-end (1- i)))
                     (if (char= (peek) #\\)
                         (progn
                           (incf i) ; consume '\'
                           (consume-escape)
                           (return-from %scan-elisp-char-literal-end (max start (1- i))))
                       (progn
                         (incf i)
                         (return-from %scan-elisp-char-literal-end (1- i)))))))))
      (let ((out-pos 0)
            (in-string nil)
            (escape nil)
            (in-comment nil)
            (token-start nil))
        (cl:values
         (with-output-to-string (out)
           (cl:loop for i from 0 below len do
             (let ((ch (char s i)))
               (cond
                (in-comment
                 (write-char ch out)
                 (cl:incf out-pos)
                 (when (char= ch #\Newline)
                   (setf in-comment nil)))

                (in-string
                 (write-char ch out)
                 (cl:incf out-pos)
                 (cond
                  (escape (setf escape nil))
                  ((char= ch #\\) (setf escape t))
                  ((char= ch #\") (setf in-string nil))))

                (t
                 (let ((delimp (delim-p ch)))
                   (cond
                    (delimp (setf token-start nil))
                    ((null token-start) (setf token-start i))))

                 (cl:block handled
                   (when (and (char= ch #\?) (eql token-start i))
                     (let* ((start i)
                            (end (%scan-elisp-char-literal-end start))
                            (seg (subseq s start (1+ end))))
                       (write-string seg out)
                       (cl:incf out-pos (length seg))
                       (setf token-start nil)
                       (setf i end))
                     (return-from handled))

                   (cond
                    ((char= ch #\;)
                     (setf in-comment t)
                     (write-char ch out)
                     (cl:incf out-pos))
                    ((char= ch #\")
                     (setf in-string t)
                     (write-char ch out)
                     (cl:incf out-pos))
                    ((char= ch #\?)
                     (let* ((prev (and (cl:> i 0) (char s (cl:1- i))))
                            (already-escapedp (and prev (char= prev #\\)))
                            (token-internalp (and token-start (cl:< token-start i))))
                       (if (or already-escapedp (not token-internalp))
                           (progn
                             (write-char ch out)
                             (cl:incf out-pos))
                         (progn
                           (cl:push out-pos insertions)
                           (write-char #\\ out)
                           (write-char #\? out)
                           (cl:incf out-pos 2)))))
                    ((char= ch #\:)
                     (let* ((prev (and (cl:> i 0) (char s (cl:1- i))))
                            (next (and (cl:< i (cl:1- len)) (char s (cl:1+ i))))
                            (keywordp (and (eql token-start i)
                                           next
                                           (not (delim-p next))))
                            (dispatch-uninternedp
                              (and token-start
                                   (cl:= i (cl:1+ token-start))
                                   (char= (char s token-start) #\#)))
                            (allowed-package-colonp
                              (and next
                                   (not (delim-p next))
                                   (%allowed-package-prefix-p token-start i)))
                            (already-escapedp (and prev (char= prev #\\))))
                       (if (or already-escapedp keywordp dispatch-uninternedp allowed-package-colonp)
                           (progn
                             (write-char ch out)
                             (cl:incf out-pos))
                         (progn
                           (cl:push out-pos insertions)
                           (write-char #\\ out)
                           (write-char #\: out)
                           (cl:incf out-pos 2)))))
                    (t
                     (write-char ch out)
                     (cl:incf out-pos)))))))))
         (nreverse insertions))))))

(cl:declaim
 (ftype (cl:function (cl:string) (cl:values cl:string list))
        %sanitize-elisp-source/colon-tokens))

(cl:defun %count-insertions-before (insertions pos)
  (cl:loop for ins in insertions
           while (cl:< ins pos)
           count 1))

(cl:defun load-elisp-file (path &key (package (find-package "ELISP")) (max-forms nil))
  (let ((raw (uiop:read-file-string path :external-format :utf-8)))
    (multiple-value-bind (sanitized _insertions)
        (%sanitize-elisp-source/colon-tokens raw)
      (declare (cl:ignore _insertions)
               (cl:type cl:string sanitized))
      (with-input-from-string (in sanitized)
        (let* ((*package* package)
               (*readtable* (%ensure-elisp-readtable))
               (load-file-name (namestring path))
               (current-load-list nil)
               (debug-file (uiop:getenv "CLEMACS_LOAD_DEBUG_FILE"))
               (debugp (or debug-file (and (uiop:getenv "CLEMACS_LOAD_DEBUG") t))))
          (declare (special load-file-name current-load-list load-history))
          (flet ((%maybe-log-load-error (e form-index)
                   (when debugp
                     (let ((out (if debug-file
                                    (open debug-file
                                          :direction :output
                                          :if-exists :append
                                          :if-does-not-exist :create)
                                    *standard-output*)))
                       (unwind-protect
                           (progn
                             (cl:format out "[clemacs:load] error in ~A form ~D: ~A~%"
                                        path form-index e)
                             #+sbcl
                             (sb-debug:print-backtrace :stream out :count 80)
                             (finish-output out))
                         (when debug-file
                           (ignore-errors (close out))))))))
            (let ((ok nil))
              (unwind-protect
                  (progn
                    (loop with form-index = 0 do
                      (let ((form
                              (handler-case
                                  (cl:read in nil :eof)
                                (cl:error (e)
                                  (let ((next-index (1+ form-index)))
                                    (%maybe-log-load-error e next-index)
                                    (let ((inv (inventory-entry-for-condition
                                                e
                                                :start-dir (uiop:pathname-directory-pathname path))))
                                      (cl:error 'elisp-load-error
                                                :path path
                                                :form-index next-index
                                                :form :read-error
                                                :cause e
                                                :inventory-entry inv)))))))
                        (when (eq form :eof)
                          (setf ok t)
                          (return))
                        (incf form-index)
                        (handler-case
                            (cl:handler-bind
                                ((cl:error
                                   (lambda (e)
                                     (%maybe-log-load-error e form-index)
                                     nil)))
                              #+sbcl
                              (cl:handler-bind
                                  ((sb-kernel:redefinition-warning #'muffle-warning))
                                (cl:eval (%elisp-rewrite form)))
                              #-sbcl
                              (cl:eval (%elisp-rewrite form)))
                          (cl:error (e)
                            (let ((inv (inventory-entry-for-condition
                                        e
                                        :start-dir (uiop:pathname-directory-pathname path))))
                              (cl:error 'elisp-load-error
                                        :path path
                                        :form-index form-index
                                        :form form
                                        :cause e
                                        :inventory-entry inv))))
                        (when (and max-forms (>= form-index max-forms))
                          (setf ok t)
                          (return))))
                    (%maybe-install-post-load-shims path)
                    (setf ok t))
                ;; Minimal `load-history` support: capture `define-symbol-prop`
                ;; registrations so `symbol-file` can locate tests.
                (when ok
                  (push (cons load-file-name current-load-list) load-history))))))))))

(cl:defvar *pp-to-string-orig* nil)
(cl:defvar *pp-to-string-shim* nil)
(cl:defvar *define-key-after-orig* nil)
(cl:defvar *define-key-after-shim* nil)

(cl:defun %pp--whitespace-only-line-p (s start end)
  (and (< start end)
       (loop for i from start below end
             for ch = (char s i)
             always (or (char= ch #\Space)
                        (char= ch #\Tab)
                        (char= ch #\Return)))))

(cl:defun %pp--delete-whitespace-only-lines (s)
  (unless (cl:stringp s)
    (error "ELISP: expected CL string, got: ~S" (type-of s)))
  (let ((len (length s)))
    (with-output-to-string (out)
      (let ((i 0))
        (loop while (< i len) do
          (let ((nl (position #\Newline s :start i)))
            (cond
             ((null nl)
              (write-string s out :start i :end len)
              (setf i len))
             ((%pp--whitespace-only-line-p s i nl)
              ;; Drop the whole whitespace-only line, including its newline.
              (setf i (1+ nl)))
             (t
              ;; Keep the line (including its newline).
              (write-string s out :start i :end (1+ nl))
              (setf i (1+ nl))))))))))

(cl:defun %install-pp-to-string-shim ()
  "Wrap `pp-to-string' to match upstream output more closely.

This is a temporary bring-up shim: our current `pp-fill' + indentation model
can introduce whitespace-only lines.  Emacs's `pp-to-string' does not, and this
causes upstream ERT's `ert--pp-with-indentation-and-newline' to fail."
  (when (and (fboundp 'pp-to-string)
             (not (and *pp-to-string-shim*
                       (eq (fdefinition 'pp-to-string) *pp-to-string-shim*))))
    (setf *pp-to-string-orig* (fdefinition 'pp-to-string))
    (setf *pp-to-string-shim*
          (lambda (object &optional pp-function)
            (let ((s (funcall *pp-to-string-orig* object pp-function)))
              (cond
               ((cl:stringp s) (%pp--delete-whitespace-only-lines s))
               (t s)))))
    (setf (fdefinition 'pp-to-string) *pp-to-string-shim*))
  nil)

(cl:defun %install-define-key-after-shim ()
  "Wrap `define-key-after' to avoid list-keymap internals during bring-up.

Upstream `lisp/subr.el`'s `define-key-after` implementation walks list-keymap
internals.  clemacs keymaps are backed by CL structures, so the upstream list
walk can misinterpret the backing object as an alist tail and crash loads
(notably in `lisp/shell.el`).

This shim preserves the surface behavior of `define-key-after` but ignores the
ordering constraint (AFTER): we delegate to `define-key`."
  (when (and (fboundp 'define-key-after)
             (not (and *define-key-after-shim*
                       (eq (fdefinition 'define-key-after) *define-key-after-shim*))))
    (setf *define-key-after-orig* (fdefinition 'define-key-after))
    (setf *define-key-after-shim*
          (lambda (keymap key definition &optional _after)
            (declare (cl:ignore _after))
            (let ((km keymap))
              (when (and (consp km)
                         (stringp (car km))
                         (keymapp (cdr km)))
                (setf km (cdr km)))
              (define-key km key definition))))
    (setf (fdefinition 'define-key-after) *define-key-after-shim*))
  nil)

(cl:defun %maybe-install-post-load-shims (path)
  (let* ((p (and path (pathname path)))
         (name (and p (pathname-name p)))
         (type (and p (pathname-type p))))
    (when (and (stringp name) (stringp type)
               (string= (string-downcase name) "pp")
               (string= (string-downcase type) "el"))
      (%install-pp-to-string-shim)))
  (let* ((p (and path (pathname path)))
         (name (and p (pathname-name p)))
         (type (and p (pathname-type p))))
    ;; `define-key-after' in `lisp/subr.el` assumes list-keymap internals; use a
    ;; clemacs-safe shim after loading `subr.el`.
    (when (and (stringp name) (stringp type)
               (string= (string-downcase name) "subr")
               (string= (string-downcase type) "el"))
      (%install-define-key-after-shim)
      ;; `lisp/subr.el` defines its own `called-interactively-p' based on
      ;; backtrace inspection.  For clemacs bring-up, override it with a
      ;; simpler dynamic-flag implementation so upstream nadvice tests can
      ;; assert interactive context without requiring full backtrace support.
      (when (and (fboundp 'clemacs--called-interactively-p) (fboundp 'fset))
        (ignore-errors
          (fset 'called-interactively-p (cl:function clemacs--called-interactively-p)))))
    ;; Keep `macroexpand-all' stack-safe under SBCL.  `lisp/emacs-lisp/macroexp.el`
    ;; defines a full-featured expander, but it can blow the control stack while
    ;; bringing up larger preloads (e.g. lisp-mode's `let-when-compile`).  Use
    ;; our iterative bring-up version instead.
    (when (and (stringp name) (stringp type)
               (string= (string-downcase name) "macroexp")
               (string= (string-downcase type) "el")
               (boundp '*macroexpand-1-compat*)
               *macroexpand-1-compat*
               (boundp '*macroexpand-compat*)
               *macroexpand-compat*
               (boundp '*macroexpand-all-compat*)
               *macroexpand-all-compat*)
      ;; Avoid touching CL:MACROEXPAND-1/CL:MACROEXPAND (package-locked under
      ;; SBCL) if this function was compiled before ELISP shadowed the names.
      (multiple-value-bind (mx1 _status1)
          (find-symbol "MACROEXPAND-1" (find-package "ELISP"))
        (declare (cl:ignore _status1))
        (when mx1
          (setf (fdefinition mx1) *macroexpand-1-compat*)))
      (multiple-value-bind (mx _status2)
          (find-symbol "MACROEXPAND" (find-package "ELISP"))
        (declare (cl:ignore _status2))
        (when mx
          (setf (fdefinition mx) *macroexpand-compat*)))
      (setf (fdefinition 'macroexpand-all) *macroexpand-all-compat*)))
  nil)
