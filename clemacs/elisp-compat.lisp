(in-package #:elisp)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (cl:require "SB-CLTL2"))

;; Some upstream ELisp assumes these are always bound (typically set by the
;; byte-compiler or load machinery).  Bind them to NIL for bring-up so
;; macroexpansion helpers (macroexp.el, pcase.el, etc.) don't trip UNBOUND.
(cl:defvar byte-compile-current-file nil)
(cl:defvar load-file-name nil)
(cl:defvar current-load-list nil)
(cl:defvar debugger nil)
(cl:defvar emacs-basic-display nil)
(cl:defvar fill-prefix nil)
(cl:defvar last-command nil)
(cl:defvar text-property-default-nonsticky nil)
(cl:defvar comment-start-skip nil)

(cl:defmacro bound-and-true-p (var)
  "Bring-up subset of ELisp `bound-and-true-p'."
  `(and (cl:boundp ',var) ,var))

(cl:defmacro interactive (&rest _spec)
  "Bring-up stub for ELisp `interactive'.

For now, clemacs runs all ELisp non-interactively, so this expands to NIL
without evaluating the interactive spec."
  (declare (cl:ignore _spec))
  nil)

(cl:defmacro defvar (var &optional init doc)
  "ELisp-ish DEFVAR.

Accepts unibyte/multibyte docstrings and coerces them to a CL string so SBCL
recognizes them as docstrings (keeping subsequent DECLARE forms legal)."
  (let ((doc* (and doc
                   (if (cl:stringp doc) doc (%elisp-string->cl-string doc)))))
    (cond
     ((and (null init) (null doc*))
      `(cl:defvar ,var))
     ((null doc*)
      `(cl:defvar ,var ,init))
     (t
      `(cl:defvar ,var ,init ,doc*)))))

(cl:defun symbol-name (sym)
  "ELisp-ish SYMBOL-NAME that returns lowercase names by default."
  (let* ((name (string-downcase (cl:symbol-name sym))))
    ;; Emacs returns unibyte strings for ASCII-only symbol names.
    (if (every (lambda (ch) (< (char-code ch) 128)) name)
        (let ((out (%make-unibyte-string (length name))))
          (dotimes (i (length name))
            (setf (aref out i) (char-code (char name i))))
          out)
        name)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Some upstream ELisp (notably regexp-opt.el) uses `string-lessp'.  If we
  ;; leave this unshadowed, the ELISP package inherits CL:STRING-LESSP, which
  ;; doesn't accept our unibyte string representation.
  (cl:shadow 'string-lessp (find-package "ELISP")))

(cl:defun string-lessp (s1 s2 &optional _start1 _end1 _start2 _end2)
  "Bring-up subset of ELisp `string-lessp'."
  (declare (cl:ignore _start1 _end1 _start2 _end2))
  (unless (and (stringp s1) (stringp s2))
    (error "ELISP:STRING-LESSP expects strings, got: %S %S" s1 s2))
  (cl:string< (%elisp-string->cl-string s1)
              (%elisp-string->cl-string s2)))

(cl:defun try-completion (string collection &optional _predicate)
  "Bring-up subset of the C primitive `try-completion'.

This currently only supports COLLECTION as a list of strings."
  (declare (cl:ignore _predicate))
  (unless (stringp string)
    (error "ELISP:TRY-COMPLETION expects STRING, got: %S" string))
  (unless (listp collection)
    (error "ELISP:TRY-COMPLETION only supports list collections, got: %S" collection))
  (let* ((prefix (%elisp-string->cl-string string))
         (cands nil))
    (dolist (s collection)
      (when (stringp s)
        (let ((cs (%elisp-string->cl-string s)))
          (when (and (<= (length prefix) (length cs))
                     (cl:string= prefix cs :end2 (length prefix)))
            (push cs cands)))))
    (when (null cands)
      (return-from try-completion nil))
    (let ((common (copy-seq (first cands))))
      (dolist (s (rest cands))
        (let ((n (mismatch common s)))
          (when n
            (setf common (subseq common 0 n)))))
      ;; Emacs returns unibyte strings for ASCII-only completions.
      (if (every (lambda (ch) (< (char-code ch) 128)) common)
          (string-to-unibyte common)
          common))))

(cl:defun all-completions (string collection &optional _predicate)
  "Bring-up subset of the C primitive `all-completions'.

This currently only supports COLLECTION as a list of strings."
  (declare (cl:ignore _predicate))
  (unless (stringp string)
    (error "ELISP:ALL-COMPLETIONS expects STRING, got: %S" string))
  (unless (listp collection)
    (error "ELISP:ALL-COMPLETIONS only supports list collections, got: %S" collection))
  (let* ((prefix (%elisp-string->cl-string string))
         (out nil))
    (dolist (s collection)
      (when (stringp s)
        (let ((cs (%elisp-string->cl-string s)))
          (when (and (<= (length prefix) (length cs))
                     (cl:string= prefix cs :end2 (length prefix)))
            (push s out)))))
    (nreverse out)))

(cl:defun intern (name &optional (package *package*))
  "ELisp-ish INTERN; canonicalizes strings to CL-style names.

This is a pragmatic compatibility shim, not a full obarray model."
  (etypecase name
    ((or cl:string unibyte-string)
     (cl:intern (string-upcase (%elisp-string->cl-string name)) package))
    (symbol name)))

(cl:defun intern-soft (name &optional _obarray)
  "Bring-up subset of ELisp `intern-soft'."
  (declare (cl:ignore _obarray))
  (unless (stringp name)
    (error "ELISP:INTERN-SOFT expects a string, got: ~S" name))
  (multiple-value-bind (sym status)
      (find-symbol (string-upcase (%elisp-string->cl-string name)) (find-package "ELISP"))
    (declare (cl:ignore status))
    sym))

(cl:defun make-symbol (name)
  "ELisp-ish MAKE-SYMBOL."
  (unless (stringp name)
    (error "ELISP:MAKE-SYMBOL expects a string, got: ~S" name))
  (cl:make-symbol (%elisp-string->cl-string name)))

(cl:defun gensym (&optional x)
  "ELisp-ish GENSYM.

Accepts a numeric counter or a string prefix (including unibyte strings)."
  (cond
   ((null x) (cl:gensym))
   ((integerp x) (cl:gensym x))
   ((stringp x) (cl:gensym (%elisp-string->cl-string x)))
   ((symbolp x) (cl:gensym (%elisp-string->cl-string (symbol-name x))))
   (t (error "ELISP:GENSYM unsupported arg: ~S" x))))

(cl:defun ignore (&rest _args)
  "ELisp `ignore': ignore ARGS and return nil."
  (declare (cl:ignore _args))
  nil)

(cl:defun mapatoms (function &optional _obarray)
  "Bring-up subset of ELisp `mapatoms'.

Emacs iterates the current obarray; for bring-up we approximate this by
iterating all symbols accessible in the ELISP package."
  (declare (cl:ignore _obarray))
  (let ((pkg (find-package "ELISP")))
    (do-symbols (s pkg)
      (cl:funcall function s)))
  nil)

(cl:defmacro function (&environment env arg)
  "ELisp-ish FUNCTION.

Emacs Lisp's `function' special form is more of a \"function designator\"
than a strict CL:FUNCTION: for symbols, it yields the symbol (resolved later
by `funcall' / `apply').  For lambdas, we keep the form as data so early
bootstrap loads don't macroexpand/compile lambda bodies."
  (cond
   ((symbolp arg)
    (multiple-value-bind (_kind localp _decls)
        (sb-cltl2:function-information arg env)
      (declare (cl:ignore _kind _decls))
      ;; If there's a local function binding (e.g. `cl-labels' / `labels'),
      ;; preserve it by producing a real CL function object.  Otherwise keep
      ;; the ELisp behavior where symbols act as function designators.
      (if localp
          `(cl:function ,arg)
          `(quote ,arg))))
   ((and (consp arg) (eq (car arg) 'lambda))
    `(quote ,arg))
   ((and (consp arg) (eq (car arg) '|,|) (null (cddr arg)))
    (cadr arg))
   ((and (consp arg) (eq (car arg) '|,@|) (null (cddr arg)))
    (cadr arg))
   (t
    `(quote ,arg))))

(defvar *elisp-function-cells* (cl:make-hash-table :test 'eq))

(cl:defun symbol-function (symbol)
  "ELisp-ish SYMBOL-FUNCTION.

Returns NIL if SYMBOL has no function cell value."
  (multiple-value-bind (value presentp)
      (gethash symbol *elisp-function-cells*)
    (cond
     (presentp value)
     ((cl:macro-function symbol)
      (cons 'macro (cl:macro-function symbol)))
     ((cl:fboundp symbol) (cl:symbol-function symbol))
     (t nil))))

(cl:defun fboundp (symbol)
  "ELisp-ish FBOUNDP."
  (multiple-value-bind (value presentp)
      (gethash symbol *elisp-function-cells*)
    (if presentp
        (not (null value))
        (cl:fboundp symbol))))

(cl:defun function-alias-p (symbol)
  "Bring-up subset of ELisp `function-alias-p'.

Returns a list of alias targets for SYMBOL's function cell, following chains
like: (defalias 'string= 'string-equal)."
  (unless (symbolp symbol)
    (return-from function-alias-p nil))
  (let ((seen (list symbol))
        (cur symbol)
        (out nil))
    (loop repeat 16 do
      (let ((next (handler-case
                      (symbol-function cur)
                    (elisp-signal (e)
                      (if (eq (elisp-signal-symbol e) 'void-function)
                          nil
                          (cl:error e))))))
        (unless (and (symbolp next) (not (eq next cur)))
          (return (nreverse out)))
        (when (member next seen :test #'eq)
          (return (nreverse out)))
        (push next seen)
        (push next out)
        (setf cur next)))))

(cl:defun %resolve-function (fn &key (max-hops 16))
  (loop with cur = fn
        for hop from 0 below max-hops do
          (cond
           ((functionp cur) (return cur))
           ((and (consp cur) (eq (car cur) 'lambda))
            (return (cl:eval `(cl:function ,cur))))
           ((symbolp cur)
            (let ((next (symbol-function cur)))
              (when (null next)
                (signal 'void-function (list cur)))
              (setf cur next)))
           (t
            (error "ELISP: function cell is not callable: ~S" cur)))
        finally
          (error "ELISP: function indirection loop for ~S" fn)))

(cl:defun funcall (fn &rest args)
  "ELisp-ish FUNCALL that accepts symbols and lambda forms."
  (cl:apply (%resolve-function fn) args))

(cl:defun eval (form &optional lexical)
  "ELisp-ish EVAL.

ELisp `eval' accepts an optional LEXICAL argument; for bring-up we ignore it
and evaluate the (already CL-shaped) FORM."
  (declare (cl:ignore lexical))
  (cl:eval (%elisp-rewrite form)))

(cl:defun sxhash-equal (object)
  "Compatibility shim for the C primitive `sxhash-equal'."
  (cl:sxhash object))

(cl:defun % (x y)
  "Bring-up subset of ELisp `%'."
  (unless (and (integerp x) (integerp y))
    (error "ELISP:% expects integers, got: ~S ~S" x y))
  (cl:rem x y))

(defconstant +char-table-size+ 65536)

(cl:defstruct (elisp-char-table
               (:constructor %make-elisp-char-table (type default data extra parent)))
  (type nil :type t)
  (default nil :type t)
  (data (make-array +char-table-size+ :initial-element nil) :type simple-vector)
  (extra (make-array 0 :adjustable t :fill-pointer 0) :type vector)
  (parent nil :type t))

(cl:defun %char-table-ref (table idx)
  (unless (and (integerp idx) (<= 0 idx) (< idx +char-table-size+))
    (error "ELISP: char-table index out of range: ~S" idx))
  (let ((val (svref (elisp-char-table-data table) idx)))
    (cond
     ((not (null val)) val)
     ((not (null (elisp-char-table-parent table)))
      (%char-table-ref (elisp-char-table-parent table) idx))
     (t (elisp-char-table-default table)))))

(cl:defun %char-table-set (table idx value)
  (unless (and (integerp idx) (<= 0 idx) (< idx +char-table-size+))
    (error "ELISP: char-table index out of range: ~S" idx))
  (setf (svref (elisp-char-table-data table) idx) value)
  value)

(cl:defun set-char-table-range (table range value)
  "Bring-up subset of ELisp `set-char-table-range'."
  (unless (char-table-p table)
    (error "ELISP:SET-CHAR-TABLE-RANGE expects a char-table, got: ~S" table))
  (cond
   ((eq range t)
    (setf (elisp-char-table-default table) value)
    value)
   ((integerp range)
    (%char-table-set table range value))
   ((characterp range)
    (%char-table-set table (char-code range) value))
   ((and (consp range) (integerp (car range)) (integerp (cdr range)))
    (let ((from (car range))
          (to (cdr range)))
      (when (> from to)
        (error "ELISP:SET-CHAR-TABLE-RANGE bad range: ~S" range))
      (loop for i from from to to do
        (%char-table-set table i value))
      value))
   (t
    (error "ELISP:SET-CHAR-TABLE-RANGE bad range: ~S" range))))

(cl:defun map-char-table (function table)
  "Bring-up subset of ELisp `map-char-table'."
  (unless (char-table-p table)
    (error "ELISP:MAP-CHAR-TABLE expects a char-table, got: ~S" table))
  (let ((default (elisp-char-table-default table)))
    (labels ((emit (start end val)
               (when (and start end (not (cl:equal val default)))
                 (funcall function
                          (if (= start end) start (cons start end))
                          val))))
      (let ((run-start 0)
            (run-val (%char-table-ref table 0)))
        (loop for i from 1 below +char-table-size+ do
          (let ((v (%char-table-ref table i)))
            (unless (cl:equal v run-val)
              (emit run-start (1- i) run-val)
              (setf run-start i
                    run-val v))))
        (emit run-start (1- +char-table-size+) run-val))))
  nil)

(cl:defun aref (array idx)
  "ELisp-ish AREF.

For strings, return a character code integer (Emacs Lisp semantics)."
  (cond
   ((typep array 'elisp-char-table) (%char-table-ref array idx))
   ((unibyte-string-p array) (cl:aref array idx))
   ((cl:stringp array) (%elisp-char-code (cl:aref array idx)))
   (t (cl:aref array idx))))

(cl:defun (setf aref) (value array idx)
  "Set ARRAY element IDX to VALUE and return VALUE (ELisp-ish)."
  (cond
   ((typep array 'elisp-char-table)
    (%char-table-set array idx value))
   ((unibyte-string-p array)
    (unless (and (integerp value) (<= 0 value 255))
      (error "ELISP:AREF set expects byte 0..255 for unibyte string, got: ~S" value))
    (setf (cl:aref array idx) value))
   ((cl:stringp array)
    (setf (char array idx) (%elisp-code->char value)))
   (t
    (setf (cl:aref array idx) value)))
  value)

(cl:defun char-to-string (ch)
  "Bring-up subset of ELisp `char-to-string'."
  (cond
   ((integerp ch) (string (%elisp-code->char ch)))
   ((characterp ch) (string ch))
   (t (error "ELISP:CHAR-TO-STRING expects character code, got: ~S" ch))))

(cl:defun concat (&rest parts)
  "Stub for ELisp `concat'."
  ;; Minimal type-correctness: if all emitted character codes are ASCII, return a
  ;; unibyte string; otherwise return a multibyte CL string.
  (let ((codes (make-array 0 :element-type 'integer :adjustable t :fill-pointer 0))
        (need-multibyte nil))
    (labels ((emit-code (code)
               (vector-push-extend code codes)
               (when (or (%raw-byte-char-code-p code) (>= code 128))
                 (setf need-multibyte t)))
             (emit-string (s)
               (cond
                ((unibyte-string-p s)
                 (dotimes (i (length s))
                   (emit-code (aref s i))))
                (t
                 (dotimes (i (length s))
                   (emit-code (%elisp-char-code (char s i)))))))
             (emit-object (o)
               ;; Force multibyte for non-string objects to avoid accidental
               ;; unibyte/encoding surprises during bring-up.
               (emit-string (string-to-multibyte (princ-to-string o)))))
      (dolist (p parts)
        (typecase p
          (null nil)
          ((or cl:string unibyte-string) (emit-string p))
          (character (emit-code (char-code p)))
          (integer (emit-code p))
          (t (emit-object p))))
      (if (not need-multibyte)
          (let ((out (%make-unibyte-string (length codes))))
            (dotimes (i (length codes))
              (setf (aref out i) (aref codes i)))
            out)
          (let ((out (cl:make-string (length codes))))
            (dotimes (i (length codes))
              (setf (char out i) (%elisp-code->char (aref codes i))))
            out)))))

(cl:defun vconcat (&rest seqs)
  "Bring-up subset of ELisp `vconcat'."
  (let ((out nil))
    (dolist (s seqs)
      (cond
       ((null s) nil)
       ((vectorp s)
        (dotimes (i (length s))
          (push (aref s i) out)))
       ((stringp s)
        (dotimes (i (length s))
          (push (aref s i) out)))
       ((consp s)
        (dolist (x s) (push x out)))
       (t
        (error "ELISP:VCONCAT unsupported sequence: ~S" (type-of s)))))
    (coerce (nreverse out) 'vector)))

(cl:defun downcase (s)
  "Bring-up subset of ELisp `downcase'."
  (unless (stringp s)
    (error "ELISP:DOWNCASE expects a string, got: ~S" s))
  (cond
   ((unibyte-string-p s)
    (let ((out (%make-unibyte-string (length s))))
      (dotimes (i (length s))
        (let ((b (aref s i)))
          (setf (aref out i)
                (cond
                 ((<= (char-code #\A) b (char-code #\Z)) (+ b 32))
                 (t b)))))
      out))
   (t (string-downcase s))))

(cl:defun upcase (s)
  "Bring-up subset of ELisp `upcase'."
  (unless (stringp s)
    (error "ELISP:UPCASE expects a string, got: ~S" s))
  (cond
   ((unibyte-string-p s)
    (let ((out (%make-unibyte-string (length s))))
      (dotimes (i (length s))
        (let ((b (aref s i)))
          (setf (aref out i)
                (cond
                 ((<= (char-code #\a) b (char-code #\z)) (- b 32))
                 (t b)))))
      out))
   (t (string-upcase s))))

(cl:defun string= (a b)
  "ELisp-ish STRING=.

Unlike CL:STRING-EQUAL, Emacs's `string-equal' is case-sensitive (an alias of
`string=')."
  (let ((a (if (symbolp a) (symbol-name a) a))
        (b (if (symbolp b) (symbol-name b) b)))
    (unless (and (stringp a) (stringp b))
      (error "ELISP:STRING= expects strings or symbols, got: ~S ~S" a b))
    (cond
     ((and (unibyte-string-p a) (unibyte-string-p b))
      (and (= (length a) (length b))
           (loop for i from 0 below (length a)
                 always (= (aref a i) (aref b i)))))
     ((and (cl:stringp a) (cl:stringp b))
      (cl:string= a b))
     (t
      ;; Match Emacs behavior: compare after promoting unibyte to multibyte.
      (cl:string=
       (string-to-multibyte a)
       (string-to-multibyte b))))))

(cl:defun string-equal (a b)
  "ELisp-ish STRING-EQUAL (case-sensitive; alias of `string=')."
  (string= a b))

(cl:defun %plist-put-preserve (plist key value)
  (loop for cell on plist by #'cddr do
    (when (eq (car cell) key)
      (setf (cadr cell) value)
      (return plist)))
  (append plist (list key value)))

(cl:defvar *buffer-text-properties*
  (cl:make-hash-table :test 'eq))

(cl:defun %buffer-text-properties (buffer)
  (gethash buffer *buffer-text-properties*))

(cl:defun %set-buffer-text-properties (buffer intervals)
  (setf (gethash buffer *buffer-text-properties*) intervals)
  buffer)

(cl:defun %clear-buffer-text-properties (buffer)
  (remhash buffer *buffer-text-properties*)
  buffer)

(cl:defun %intervals-properties-at (pos intervals)
  (let ((out nil))
    ;; Apply intervals in order, preserving key position on updates.
    (dolist (iv intervals)
      (when (and (<= (elisp::text-prop-interval-start iv) pos)
                 (< pos (elisp::text-prop-interval-end iv)))
        (loop for (k v) on (elisp::text-prop-interval-plist iv) by #'cddr do
          (setf out (%plist-put-preserve out k v)))))
    out))

(cl:defun text-properties-at (pos &optional object)
  "Bring-up subset of ELisp `text-properties-at'."
  (let ((obj (or object (current-buffer))))
    (cond
     ((stringp obj)
      (unless (and (integerp pos) (not (minusp pos)))
        (error "ELISP:TEXT-PROPERTIES-AT bad position: ~S" pos))
      (let ((len (length obj)))
        (when (> pos len)
          (error "ELISP:TEXT-PROPERTIES-AT out of range: ~S (len ~S)" pos len))
        (let ((intervals (elisp::%string-text-properties obj)))
          (when (null intervals)
            (return-from text-properties-at nil))
          (%intervals-properties-at pos intervals))))
     ((bufferp obj)
      (let* ((pos* (%pos pos))
             (pmax (1+ (length (elisp-buffer-text obj)))))
        (unless (and (integerp pos*) (plusp pos*))
          (error "ELISP:TEXT-PROPERTIES-AT bad position: ~S" pos))
        (when (> pos* pmax)
          (error "ELISP:TEXT-PROPERTIES-AT out of range: ~S (max ~S)" pos* pmax))
        (let ((intervals (%buffer-text-properties obj)))
          (when (null intervals)
            (return-from text-properties-at nil))
          (%intervals-properties-at pos* intervals))))
     (t
      (error "ELISP:TEXT-PROPERTIES-AT unsupported OBJECT: ~S" obj)))))

(cl:defun get-text-property (pos prop &optional object)
  "Bring-up subset of ELisp `get-text-property'."
  (plist-get (text-properties-at pos object) prop))

(cl:defun put-text-property (start end prop value &optional object)
  "Bring-up subset of ELisp `put-text-property'."
  (let ((obj (or object (current-buffer))))
    (cond
     ((stringp obj)
      (unless (and (integerp start) (integerp end) (<= 0 start) (<= start end))
        (error "ELISP:PUT-TEXT-PROPERTY bad range: ~S..~S" start end))
      (let ((len (length obj)))
        (when (> end len)
          (error "ELISP:PUT-TEXT-PROPERTY out of range: ~S..~S (len ~S)" start end len))
        (when (< start end)
          (let* ((old (or (elisp::%string-text-properties obj) nil))
                 (iv (elisp::make-text-prop-interval
                      :start start
                      :end end
                      :plist (list prop value))))
            (elisp::%set-string-text-properties obj (append old (list iv)))))))
     ((bufferp obj)
      (let* ((s (%pos start))
             (e (%pos end))
             (pmax (1+ (length (elisp-buffer-text obj)))))
        (unless (and (integerp s) (integerp e) (plusp s) (<= s e))
          (error "ELISP:PUT-TEXT-PROPERTY bad range: ~S..~S" start end))
        (when (> e pmax)
          (error "ELISP:PUT-TEXT-PROPERTY out of range: ~S..~S (max ~S)" s e pmax))
        (when (< s e)
          (let* ((old (or (%buffer-text-properties obj) nil))
                 (iv (elisp::make-text-prop-interval
                      :start s
                      :end e
                      :plist (list prop value))))
            (%set-buffer-text-properties obj (append old (list iv)))))))
     (t
      (error "ELISP:PUT-TEXT-PROPERTY unsupported OBJECT: ~S" obj))))
  t)

(cl:defun add-text-properties (start end props &optional object)
  "Bring-up subset of ELisp `add-text-properties'."
  (unless (and (listp props) (evenp (length props)))
    (error "ELISP:ADD-TEXT-PROPERTIES expects a plist, got: ~S" props))
  (loop for (k v) on props by #'cddr do
    (put-text-property start end k v object))
  t)

(cl:defun substring-no-properties (string &optional (from 0) to)
  "Bring-up subset of ELisp `substring-no-properties' (for strings)."
  (let ((s (substring string from to)))
    (elisp::%clear-string-text-properties s)
    s))

(cl:defun propertize (string &rest properties)
  "Bring-up subset of ELisp `propertize' (for strings)."
  (unless (stringp string)
    (error "ELISP:PROPERTIZE expects a string, got: ~S" string))
  (unless (evenp (length properties))
    (error "ELISP:PROPERTIZE expects a property list, got: ~S" properties))
  (let ((s (copy-seq string)))
    (elisp::%clear-string-text-properties s)
    (when properties
      (elisp::%set-string-text-properties
       s
       (list (elisp::make-text-prop-interval
              :start 0
              :end (length s)
              :plist properties))))
    s))

(cl:defun equal-including-properties (a b)
  "Bring-up subset of ELisp `equal-including-properties'."
  (cond
   ((and (stringp a) (stringp b))
    ;; `equal-including-properties' must compare string contents independent of
    ;; text properties, then compare properties at each position.
    (when (not (equal a b))
      (return-from equal-including-properties nil))
    (let ((len (length a)))
      (loop for i from 0 to len do
        (unless (equal (text-properties-at i a) (text-properties-at i b))
          (return-from equal-including-properties nil)))
      t))
   (t
    (equal a b))))

(cl:defun capitalize (s)
  "Bring-up subset of ELisp `capitalize'."
  (unless (stringp s)
    (error "ELISP:CAPITALIZE expects a string, got: ~S" s))
  (cond
   ((unibyte-string-p s)
    (let* ((cl-s (%elisp-string->cl-string s))
           (out (string-capitalize cl-s)))
      (string-to-unibyte out)))
   (t
    (string-capitalize s))))

(cl:defun substring (s from &optional to)
  "Bring-up subset of ELisp `substring' for strings.

Supports negative indices and TO = nil (meaning end of string)."
  (unless (stringp s)
    (error "ELISP:SUBSTRING expects a string, got: ~S" s))
  (unless (integerp from)
    (error "ELISP:SUBSTRING expects integer FROM, got: ~S" from))
  (let* ((n (length s))
         (start (if (minusp from) (+ n from) from))
         (end (cond
               ((null to) n)
               ((integerp to) (if (minusp to) (+ n to) to))
               (t (error "ELISP:SUBSTRING expects integer or nil TO, got: ~S" to)))))
    (when (or (< start 0) (> start n) (< end 0) (> end n) (< end start))
      (signal 'args-out-of-range (list s from to)))
    (subseq s start end)))

(cl:defvar emacs-version "31.0.50")

(cl:defvar lexical-binding t)

(cl:defvar case-fold-search nil)

(defvar *match-data* nil)
(defvar *match-source-string* nil)
(defvar *string-match-scanner-cache* (cl:make-hash-table :test #'cl:equal))
(defvar *string-match-anchored-scanner-cache* (cl:make-hash-table :test #'cl:equal))

(cl:defun match-data ()
  "Bring-up subset of ELisp `match-data'."
  (and *match-data* (copy-list *match-data*)))

(cl:defun set-match-data (data &optional _reseat _inhibit-read-only)
  "Bring-up subset of ELisp `set-match-data'."
  (declare (cl:ignore _reseat _inhibit-read-only))
  (setf *match-data* (and data (copy-list data)))
  nil)

(cl:defun match-beginning (n)
  "Bring-up subset of ELisp `match-beginning'."
  (unless (and (integerp n) (<= 0 n))
    (error "ELISP:MATCH-BEGINNING expects non-negative integer, got: %S" n))
  (let ((i (* 2 n)))
    (and *match-data* (< i (length *match-data*)) (nth i *match-data*))))

(cl:defun match-end (n)
  "Bring-up subset of ELisp `match-end'."
  (unless (and (integerp n) (<= 0 n))
    (error "ELISP:MATCH-END expects non-negative integer, got: %S" n))
  (let ((i (1+ (* 2 n))))
    (and *match-data* (< i (length *match-data*)) (nth i *match-data*))))

(cl:defun match-string (n &optional string)
  "Bring-up subset of ELisp `match-string'."
  (unless (and (integerp n) (<= 0 n))
    (error "ELISP:MATCH-STRING expects non-negative integer, got: %S" n))
  (let* ((start (match-beginning n))
         (end (match-end n)))
    (when (or (null start) (null end))
      (return-from match-string nil))
    ;; If STRING is non-nil, Emacs uses match positions as 0-based indices into
    ;; that string (as set by `string-match').
    (cond
     (string
      (substring string start end))
     ;; When the last match came from `string-match', it stashes the searched
     ;; string in `*match-source-string*'.
     (*match-source-string*
      (substring *match-source-string* start end))
     ;; Otherwise, assume the last match came from a buffer regexp operation
     ;; like `looking-at' or `re-search-forward', and use buffer positions.
     (t
      (buffer-substring start end)))))

(cl:defun %elisp-regexp->pcre (regexp)
  "Translate a (very) small subset of Emacs regexps to PCRE.

Key rule: Emacs uses backslash escapes for grouping/alternation
(`\\(...\\)' and `\\|'), while unescaped parens and | are literals.
PCRE uses unescaped parens/| as metacharacters.

So we:
- convert escaped Emacs grouping/alternation to PCRE metacharacters,
- escape otherwise-unescaped PCRE metacharacters to preserve literal meaning,
- translate `\\` and `\\'' anchors to ^/$."
  (let ((regexp (%elisp-string->cl-string regexp)))
    (with-output-to-string (out)
      (labels ((emit-posix-class (name)
                 ;; cl-ppcre does not support POSIX bracket expressions like
                 ;; [[:alpha:]] directly, so approximate the commonly used
                 ;; ones with ASCII ranges.
                 (let ((s (string-downcase name)))
                   (cond
                    ((string= s "alnum") (write-string "0-9A-Za-z" out))
                    ((string= s "alpha") (write-string "A-Za-z" out))
                    ((string= s "digit") (write-string "0-9" out))
                    ((string= s "lower") (write-string "a-z" out))
                    ((string= s "upper") (write-string "A-Z" out))
                    ((string= s "xdigit") (write-string "0-9A-Fa-f" out))
                    ((string= s "space") (write-string "\\s" out))
	                    ((string= s "blank") (write-string " \\t" out))
                    (t
                     ;; Unknown class: fall back to a conservative subset so
                     ;; callers don't explode during bring-up.
                     (write-string "A-Za-z" out))))))
        (loop with i = 0
              with n = (length regexp)
              with in-class = nil
            while (< i n) do
              (let ((ch (char regexp i)))
	               (cond
	                ((char= ch #\\)
	                 (incf i)
	                 (when (>= i n)
	                   (write-char #\\ out)
	                   (return))
	                 (let ((next (char regexp i)))
	                   (case next
	                     (#\( (write-char #\( out))
	                     (#\) (write-char #\) out))
	                     (#\| (write-char #\| out))
	                     (#\{ (write-char #\{ out))
	                     (#\} (write-char #\} out))
	                     ;; Emacs `\\`` and `\\'' mean beginning/end of buffer.
	                     ;; Preserve those semantics even if we later treat `^`/`$`
	                     ;; as line anchors.
	                     (#\` (write-string "\\A" out))
	                     (#\' (write-string "\\z" out))
	                     (otherwise
	                      (write-char #\\ out)
	                      (write-char next out)))))
                 ;; Character classes: preserve [...] structure and make sure we
                 ;; can include a literal `[` inside (used by pp.el).
                 ((and (not in-class) (char= ch #\[))
                  (setf in-class t)
                  (write-char ch out))
                 ((and in-class (char= ch #\]))
                  (setf in-class nil)
                  (write-char ch out))
                 ((and in-class (char= ch #\[))
                  ;; Inside a bracket expression, Emacs regexps can embed
                  ;; POSIX-style character classes like `[:alpha:]'.  cl-ppcre
                  ;; does not accept that syntax, so translate to an ASCII
                  ;; approximation.  The inner `[:...:]' construct should not
                  ;; terminate the outer bracket expression.
                  (cond
                   ((and (< (1+ i) n) (char= (char regexp (1+ i)) #\:))
                    (let ((end (search ":]" regexp :start2 (+ i 2))))
                      (if end
                          (progn
                            (emit-posix-class (subseq regexp (+ i 2) end))
                            (setf i (1+ end)))
                          (progn
                            (write-char #\\ out)
                            (write-char #\[ out)))))
                   (t
                    (write-char #\\ out)
                    (write-char #\[ out))))
	                ;; Escape PCRE metachars that are literals in Emacs regexps.
	                ((and (not in-class) (find ch "()|{}" :test #'char=))
	                 (write-char #\\ out)
	                 (write-char ch out))
	                ;; In Emacs regexps, `^`/`$` are beginning/end of *line*.
	                ;; Approximate using (?:^|(?<=\\n)) and (?:$|(?=\\n)) so we
	                ;; don't have to enable PCRE multiline globally (and can keep
	                ;; `\\``/`\\'' as strict buffer anchors via \\A/\\z).
	                ((and (not in-class) (char= ch #\^))
	                 (write-string "(?:^|(?<=\\n))" out))
	                ((and (not in-class) (char= ch #\$))
	                 (write-string "(?:$|(?=\\n))" out))
	                (t
	                 (write-char ch out))))
	             (incf i))))))

(cl:defun %string-match-scanner (regexp case-fold-search)
  (let* ((regexp (%elisp-string->cl-string regexp))
         (key (list regexp (and case-fold-search t)))
         (cached (gethash key *string-match-scanner-cache*)))
    (or cached
        (setf (gethash key *string-match-scanner-cache*)
              (cl-ppcre:create-scanner (%elisp-regexp->pcre regexp)
                                       :case-insensitive-mode
                                       (and case-fold-search t))))))

(cl:defun %string-match-anchored-scanner (regexp case-fold-search)
  "Return a scanner that only matches at the start of the searched region.

This is used for ELisp `looking-at', which must not search forward past point."
  (let* ((regexp (%elisp-string->cl-string regexp))
         (key (list regexp (and case-fold-search t)))
         (cached (gethash key *string-match-anchored-scanner-cache*)))
    (or cached
        (setf (gethash key *string-match-anchored-scanner-cache*)
              (cl-ppcre:create-scanner
               (concatenate 'cl:string "\\A(?:" (%elisp-regexp->pcre regexp) ")")
               :case-insensitive-mode
               (and case-fold-search t))))))

(cl:defun string-match (regexp string &optional start _inhibit-modify)
  "Bring-up `string-match' using cl-ppcre as a temporary regexp engine."
  (declare (cl:ignore _inhibit-modify))
  (unless (and (stringp regexp) (stringp string))
    (error "ELISP:STRING-MATCH expects strings, got: %S %S" regexp string))
  (let ((start (or start 0))
        (s (%elisp-string->cl-string string)))
    (unless (and (integerp start) (<= 0 start))
      (error "ELISP:STRING-MATCH bad start: %S" start))
    (multiple-value-bind (mstart mend reg-starts reg-ends)
        (cl-ppcre:scan (%string-match-scanner regexp case-fold-search)
                       s
                       :start start
                       ;; cl-ppcre's internal "real start" affects how anchors
                       ;; behave with :start.  Emacs anchors are not relative to
                       ;; the search start, so pin to 0.
                       :real-start-pos 0)
      (if (null mstart)
          (progn
            (setf *match-data* nil
                  *match-source-string* string)
            nil)
          (let ((md nil))
            ;; Build match data in reverse, then NREVERSE to produce:
            ;; (mstart mend g1start g1end g2start g2end ...).
            (push mstart md)
            (push mend md)
            (when reg-starts
              (loop for rs across reg-starts
                    for re across reg-ends
                    do
                      (push (and (integerp rs) (<= 0 rs) rs) md)
                      (push (and (integerp re) (<= 0 re) re) md)))
            (setf *match-data* (nreverse md)
                  *match-source-string* string)
            mstart)))))

(cl:defun string-match-p (regexp string &optional start)
  "Bring-up `string-match-p' (like `string-match' but does not modify match data)."
  (let ((saved-md *match-data*)
        (saved-s *match-source-string*))
    (unwind-protect
        (string-match regexp string start)
      (setf *match-data* saved-md
            *match-source-string* saved-s))))

(cl:defun regexp-quote (string &optional _lax)
  "Bring-up subset of the C primitive `regexp-quote'."
  (declare (cl:ignore _lax))
  (unless (stringp string)
    (error "ELISP:REGEXP-QUOTE expects a string, got: %S" string))
  ;; Preserve unibyte vs multibyte: return a unibyte string iff STRING is
  ;; unibyte (and the output stays byte-representable).
  (let* ((want-unibyte (unibyte-string-p string))
         (s (%elisp-string->cl-string string))
         (codes (make-array 0 :element-type 'integer :adjustable t :fill-pointer 0)))
    (labels ((emit (code)
               (vector-push-extend code codes)))
      (loop for ch across s do
        ;; Match Emacs: do NOT escape `|', `(', `)', `{', or `}'.
        (when (find ch "\\.[]*+?^$" :test #'char=)
          (emit (char-code #\\)))
        (emit (%elisp-char-code ch)))
      (if want-unibyte
          (let ((out (%make-unibyte-string (length codes))))
            (dotimes (i (length codes))
              (let ((b (aref codes i)))
                (unless (and (integerp b) (<= 0 b 255))
                  (error "ELISP:REGEXP-QUOTE cannot encode byte: %S" b))
                (setf (aref out i) b)))
            out)
          (let ((out (cl:make-string (length codes))))
            (dotimes (i (length codes))
              (setf (char out i) (%elisp-code->char (aref codes i))))
            out)))))

(cl:defun %rx--regexp-quote (s)
  "Very small subset of Emacs's `regexp-quote'."
  (let ((s (%elisp-string->cl-string s)))
    (with-output-to-string (out)
      (loop for ch across s do
        (when (find ch "\\.[]*+?^$" :test #'char=)
          (write-char #\\ out))
        (write-char ch out)))))

(cl:defun %rx--lookup-definition (name)
  (let ((d (and (symbolp name) (get name 'rx-definition))))
    (cond
     ((null d) nil)
     ((and (consp d) (null (cdr d))) (car d))
     (t (cons (intern ":" (find-package "ELISP")) d)))))

(cl:defun %rx--translate (form)
  ;; Return an Emacs regexp string (not PCRE). This is intentionally tiny and
  ;; only grows as startup checkpoints demand it.
  (labels ((op-name (s) (and (symbolp s) (cl:symbol-name s)))
           (op= (s name) (and (symbolp s) (string= (cl:symbol-name s) name)))
           (group (s) (concatenate 'cl:string "\\(?:" s "\\)"))
           (emit (x)
             (cond
              ((null x) "")
              ((stringp x) (%rx--regexp-quote x))
              ((symbolp x)
               (let ((def (%rx--lookup-definition x)))
                 (cond
                  (def (%rx--translate def))
                  ((memq x '(nonl not-newline any)) ".")
                  (t (error "ELISP:rx unsupported symbol: %S" x)))))
              ((consp x)
               (let ((op (car x))
                     (args (cdr x)))
                 (cond
                  ;; Sequence.
                  ((op= op ":")
                   (apply #'concatenate 'cl:string (mapcar #'emit args)))
                  ;; Alternation.
                  ((op= op "|")
                   (group
                    (with-output-to-string (out)
                      (loop for a in args
                            for firstp = t then nil do
                              (unless firstp (write-string "\\|" out))
                              (write-string (emit a) out)))))
                  ;; One-or-more.
                  ((op= op "+")
                   (cond
                    ((/= (length args) 1)
                     (error "ELISP:rx (+ ...) expects 1 arg, got: %S" x))
                    (t
                     (concatenate 'cl:string (group (emit (car args))) "+"))))
                  ;; (syntax word) / (syntax symbol): approximate for bring-up.
                  ((op= op "SYNTAX")
                   (let ((kind (car args)))
                     (cond
                      ((or (eq kind 'word) (eq kind 'symbol))
                       ;; Keep this within the subset understood by
                       ;; %elisp-regexp->pcre: POSIX classes only inside [...]
                       ;; and ASCII-only approximations.
                       "[[:alnum:]_]")
                      (t
                       (error "ELISP:rx (syntax ...) unsupported: %S" x)))))
                  (t
                   (error "ELISP:rx unsupported form: %S" x)))))
              (t
               (error "ELISP:rx unsupported object: %S" x)))))
    (emit form)))

(cl:defun %rx--runtime (forms)
  (cond
   ((null forms) "")
   ((null (cdr forms)) (%rx--translate (car forms)))
   (t
    (%rx--translate (cons (intern ":" (find-package "ELISP")) forms)))))

(cl:defmacro rx (&rest forms)
  "Bring-up subset of Emacs's `rx' macro."
  `(%rx--runtime ',forms))

(cl:defmacro rx-define (name &rest definition)
  "Bring-up subset of Emacs's `rx-define'."
  `(progn
     (put ',name 'rx-definition ',definition)
     ',name))

(cl:defun string-search (needle haystack &optional start)
  "Bring-up subset of the C primitive `string-search'."
  (unless (and (stringp needle) (stringp haystack))
    (error "ELISP:STRING-SEARCH expects strings, got: ~S ~S" needle haystack))
  (let* ((n (%elisp-string->cl-string needle))
         (h (%elisp-string->cl-string haystack))
         (start (or start 0)))
    (unless (and (integerp start) (<= 0 start) (<= start (length h)))
      (error "ELISP:STRING-SEARCH bad start: ~S" start))
    (search n h :start2 start :test #'char=)))

(cl:defvar print-escape-newlines nil)
(cl:defvar print-escape-control-characters nil)

(cl:defun prin1-to-string (object &optional _noescape)
  "Bring-up subset of ELisp `prin1-to-string'.

This is only intended to be readable by our ELisp `read-from-string'."
  (declare (cl:ignore _noescape))
  (labels ((sym-name (s)
             (cond
              ((eq s nil) "nil")
              ((eq s t) "t")
              ((eq (symbol-package s) (find-package "KEYWORD"))
               (concatenate 'cl:string ":" (string-downcase (cl:symbol-name s))))
              (t (string-downcase (cl:symbol-name s)))))
           (emit-string (s)
             (with-output-to-string (out)
               (write-char #\" out)
               (flet ((emit-hex (code)
                        (cl:format out "\\\\x~2,'0x" code)))
                 (cond
                  ((unibyte-string-p s)
                   (dotimes (i (length s))
                     (let ((b (aref s i)))
                       (case b
                         (#.(char-code #\") (write-string "\\\"" out))
                         (#.(char-code #\\) (write-string "\\\\" out))
                         (#.(char-code #\Newline)
                          (if print-escape-newlines
                              (write-string "\\n" out)
                              (write-char #\Newline out)))
                         (#.(char-code #\Tab)
                          (if print-escape-control-characters
                              (write-string "\\t" out)
                              (write-char #\Tab out)))
                         (#.(char-code #\Return)
                          (if print-escape-control-characters
                              (write-string "\\r" out)
                              (write-char #\Return out)))
                         (#.(char-code #\Backspace)
                          (if print-escape-control-characters
                              (write-string "\\b" out)
                              (write-char #\Backspace out)))
                         (#.(char-code #\Page)
                          (if print-escape-control-characters
                              (write-string "\\f" out)
                              (write-char #\Page out)))
                         (otherwise
                          (cond
                           ((and (<= 32 b 126) (not (member b (list (char-code #\") (char-code #\\)))))
                            (write-char (code-char b) out))
                           (t (emit-hex b)))))))
                   (write-char #\" out))
                  ((stringp s)
                   (dotimes (i (length s))
                     (let ((ch (char s i)))
                       (case ch
                         (#\" (write-string "\\\"" out))
                         (#\\ (write-string "\\\\" out))
                         (#\Newline
                          (if print-escape-newlines
                              (write-string "\\n" out)
                              (write-char #\Newline out)))
                         (#\Tab
                          (if print-escape-control-characters
                              (write-string "\\t" out)
                              (write-char #\Tab out)))
                         (#\Return
                          (if print-escape-control-characters
                              (write-string "\\r" out)
                              (write-char #\Return out)))
                         (#\Backspace
                          (if print-escape-control-characters
                              (write-string "\\b" out)
                              (write-char #\Backspace out)))
                         (#\Page
                          (if print-escape-control-characters
                              (write-string "\\f" out)
                              (write-char #\Page out)))
                         (otherwise
                          (let ((cc (char-code ch)))
                            (cond
                             ((<= 32 cc 126) (write-char ch out))
                             ((<= cc 255) (emit-hex cc))
                             (t (cl:format out "\\\\u~4,'0x" cc))))))))
                   (write-char #\" out))
                  (t
                   (cl:error "ELISP:PRIN1-TO-STRING expected string, got: ~S"
                             (type-of s)))))))
           (emit (x)
             (cond
              ((null x) "nil")
              ((eq x t) "t")
              ((symbolp x) (sym-name x))
              ((integerp x) (cl:princ-to-string x))
              ((characterp x) (emit-string (string x)))
              ((or (unibyte-string-p x) (cl:stringp x)) (emit-string x))
              ((and (vectorp x) (not (stringp x)))
               (with-output-to-string (out)
                 (write-char #\[ out)
                 (dotimes (i (length x))
                   (when (> i 0) (write-char #\Space out))
                   (write-string (emit (aref x i)) out))
                 (write-char #\] out)))
              ((consp x)
               (cond
                ((and (eq (car x) 'quote) (consp (cdr x)) (null (cddr x)))
                 (with-output-to-string (out)
                   (write-char #\' out)
                   (write-string (emit (cadr x)) out)))
                ((and (eq (car x) 'function) (consp (cdr x)) (null (cddr x)))
                 (with-output-to-string (out)
                   (write-string "#'" out)
                   (write-string (emit (cadr x)) out)))
                (t
               (with-output-to-string (out)
                 (write-char #\( out)
                 (labels ((walk (cell firstp)
                            (cond
                             ((null cell) nil)
                             ((consp cell)
                              (unless firstp (write-char #\Space out))
                              (write-string (emit (car cell)) out)
                              (walk (cdr cell) nil))
                             (t
                              (write-string " . " out)
                              (write-string (emit cell) out)))))
                   (walk x t))
                 (write-char #\) out)))
                ))
              ;; Emacs expects hash-tables to be printable/readable when the
              ;; feature is available. For bring-up, keep it simple: print an
              ;; empty hash-table in a read-time-eval form so `read-from-string'
              ;; can reconstruct one.
              ((cl:hash-table-p x) "#.(make-hash-table)")
              (t (cl:prin1-to-string x)))))
    (let ((print-escape-newlines (and (boundp 'print-escape-newlines) print-escape-newlines))
          (print-escape-control-characters
            (and (boundp 'print-escape-control-characters) print-escape-control-characters)))
      (emit object))))


(cl:defun read-from-string (string &optional start end)
  "Bring-up subset of ELisp `read-from-string'.

Return (OBJECT . POSITION) where POSITION is the index of the first unread
character in STRING."
  (unless (stringp string)
    (error "ELISP:READ-FROM-STRING expects a string, got: %S" string))
  (let* ((s (%elisp-string->cl-string string))
         (start (or start 0))
         (end (or end (length s))))
    (unless (and (integerp start) (<= 0 start))
      (error "ELISP:READ-FROM-STRING bad start: %S" start))
    (unless (and (integerp end) (<= start end) (<= end (length s)))
      (error "ELISP:READ-FROM-STRING bad end: %S" end))
    (let* ((sub (subseq s start end)))
      (multiple-value-bind (sanitized insertions)
          (elisp::%sanitize-elisp-source/colon-tokens sub)
        (let ((*package* (find-package "ELISP"))
              (*readtable* (elisp::%ensure-elisp-readtable))
              (*read-eval* t))
          (multiple-value-bind (obj pos)
              (cl:read-from-string sanitized nil :eof)
            (when (eq obj :eof)
              (error "ELISP:READ-FROM-STRING EOF"))
            (let* ((ins-before (%count-insertions-before insertions pos))
                   (pos* (- pos ins-before)))
              (cons obj (+ start pos*)))))))))

(cl:defun string-to-number (string)
  "Bring-up subset of ELisp `string-to-number'."
  (unless (stringp string)
    (error "ELISP:STRING-TO-NUMBER expects string, got: ~S" string))
  (handler-case
      (parse-integer (%elisp-string->cl-string string) :junk-allowed t)
    (cl:error () 0)))

(cl:defun copy-sequence (sequence)
  "ELisp-ish COPY-SEQUENCE."
  (typecase sequence
    (null nil)
    (cons (copy-list sequence))
    (cl:string (copy-seq sequence))
    (unibyte-string (copy-seq sequence))
    (vector (copy-seq sequence))
    (t (error "ELISP:COPY-SEQUENCE unsupported type: ~S" (type-of sequence)))))

(cl:defun make-hash-table (&rest args &key (test 'eql) &allow-other-keys)
  "ELisp-ish MAKE-HASH-TABLE.

Emacs Lisp accepts `:test' values like 'eq/'eql/'equal/'equalp. We map
`equal' to CL:EQUALP to get vector element semantics, which is a closer
match to Elisp than CL:EQUAL.

  Also supports SBCL weak hash tables via Emacs's `:weakness' values (e.g. 'key)."
  (unless (symbolp test)
    (error "ELISP:MAKE-HASH-TABLE only supports symbolic :test, got: ~S" test))
  (let* ((mapped-test
           (cond
            ((or (eq test 'eq) (eq test 'cl:eq)) 'cl:eq)
            ((or (eq test 'eql) (eq test 'cl:eql)) 'cl:eql)
            ((or (eq test 'equal) (eq test 'cl:equal)) 'cl:equalp)
            ((or (eq test 'equalp) (eq test 'cl:equalp)) 'cl:equalp)
            (t (error "ELISP:MAKE-HASH-TABLE unsupported :test: ~S" test))))
         ;; Always include the mapped test, even if SBCL doesn't retain :TEST in
         ;; &REST when &KEY is present.
         (out (list :test mapped-test)))
    (loop for (k v) on args by (cl:function cl:cddr) do
      (cond
       ((eq k :test) nil)
       ((eq k :weakness)
        (let ((wk
                (cond
                 ((null v) nil)
                 ((eq v :key) :key)
                 ((eq v :value) :value)
                 ((eq v :key-or-value) :key-or-value)
                 ((eq v :key-and-value) :key-and-value)
                 ((eq v 'key) :key)
                 ((eq v 'value) :value)
                 ((eq v 'key-or-value) :key-or-value)
                 ((eq v 'key-and-value) :key-and-value)
                 (t (error "ELISP:MAKE-HASH-TABLE unsupported :weakness: ~S" v)))))
          (when wk
            (setf out (nconc out (list :weakness wk))))))
       ((or (eq k :size) (eq k :rehash-size) (eq k :rehash-threshold))
        (setf out (nconc out (list k v))))
       (t nil)))
    (apply #'cl:make-hash-table out)))

(cl:defun puthash (key value table)
  "ELisp-ish PUTHASH."
  (setf (gethash key table) value)
  value)

(defparameter features nil)

(cl:defun featurep (feature)
  "Stub for ELisp `featurep'."
  (and (member feature features :test 'eq) t))

(cl:defun provide (feature &optional _subfeatures)
  "Stub for ELisp `provide'."
  (declare (cl:ignore _subfeatures))
  (pushnew feature features :test 'eq)
  feature)

(cl:defun require (feature &optional _filename _noerror)
  "Stub for ELisp `require'.

Currently does not load code; it only records FEATURE as provided."
  (declare (cl:ignore _filename _noerror))
  (unless (featurep feature)
    (provide feature))
  feature)

(cl:defmacro |`| (structure)
  "ELisp backquote reader form: (` STRUCTURE) -> (backquote STRUCTURE)."
  `(backquote ,structure))

(cl:defun backquote-list* (&rest args)
  "Run-time helper used by `lisp/emacs-lisp/backquote.el' expansions."
  (apply #'cl:list* args))

(cl:defun append (&rest seqs)
  "ELisp-ish APPEND.

Supports lists and vectors (and strings as a sequence of characters).
This is sufficient for `lisp/emacs-lisp/backquote.el', which uses
`(append VEC ())' to turn a vector into a list of its elements."
  (labels ((seq->list (x &key (copy t))
             (cond
              ((null x) nil)
              ((consp x) (if copy (copy-list x) x))
              ((vectorp x) (coerce x 'list))
              ((stringp x)
               (loop for i from 0 below (length x)
                     collect (aref x i)))
              (t (error "ELISP:APPEND unsupported type: ~S" (type-of x))))))
    (cond
     ((null seqs) nil)
     ((null (cdr seqs)) (seq->list (car seqs)))
     (t
      (let* ((last (car (last seqs)))
             (prefix (butlast seqs))
             (acc nil))
        (dolist (s prefix)
          (setf acc (nconc acc (seq->list s))))
        (if (listp last)
            (nconc acc last)
            (nconc acc (seq->list last))))))))

(cl:defmacro eval-when-compile (&rest body)
  "Bring-up stub for ELisp `eval-when-compile'.

We evaluate BODY at macro-expansion time and return a quoted constant,
matching the non-byte-compiler definition in `lisp/emacs-lisp/byte-run.el'."
  (list 'quote (cl:eval (cons 'progn body))))

(cl:defmacro eval-and-compile (&rest body)
  "Bring-up stub for ELisp `eval-and-compile'.

We evaluate BODY at macro-expansion time and return a quoted constant,
matching the non-byte-compiler definition in `lisp/emacs-lisp/byte-run.el'."
  (list 'quote (cl:eval (cons 'progn body))))

;; ---------------------------------------------------------------------------
;; Minimal pcase subset (bring-up)
;;
;; Goal: support the common `pcase-dolist' destructuring patterns used across
;; the shipped ELisp tree, without pulling in the full upstream `pcase.el'
;; machinery yet.
;;
;; This is intentionally a subset. The plan is to eventually load and run the
;; upstream `lisp/emacs-lisp/pcase.el' implementation under clemacs, at which
;; point these stubs should become unused/overridden.
;; ---------------------------------------------------------------------------

(cl:defun %pcase--dontcare-p (pat)
  (and (symbolp pat) (or (eq pat '_) (eq pat t) (eq pat 'pcase--dontcare))))

(cl:defun %pcase--comma-form-p (x)
  (and (consp x) (symbolp (car x)) (string= (symbol-name (car x)) ",")))

(cl:defun %pcase--comma-at-form-p (x)
  (and (consp x) (symbolp (car x)) (string= (symbol-name (car x)) ",@")))

(cl:defun %pcase--bq-form-p (x)
  (and (consp x) (symbolp (car x)) (string= (symbol-name (car x)) "`")))

(cl:defun %pcase--collect-vars (pat)
  (let ((vars nil))
    (labels ((walk (p)
               (cond
                ((%pcase--dontcare-p p) nil)
                ((symbolp p) (pushnew p vars :test #'eq))
                ((%pcase--comma-form-p p)
                 (when (= (length p) 2) (walk (cadr p))))
                ((%pcase--comma-at-form-p p)
                 (when (= (length p) 2) (walk (cadr p))))
                ((%pcase--bq-form-p p)
                 (when (= (length p) 2) (walk (cadr p))))
                ((consp p)
                 (walk (car p))
                 (walk (cdr p)))
                (t nil))))
      (walk pat))
    (nreverse vars)))

(cl:defun %pcase--template->lambda-list (tmpl)
  "Translate a backquote template TMPL into a destructuring-bind lambda list.

Returns (values LAMBDA-LIST CHECKS BINDINGS), where:
- LAMBDA-LIST is suitable for CL:DESTRUCTURING-BIND.
- CHECKS is a list of forms (in terms of the destructured vars) that must hold.
- BINDINGS is the list of ELisp variables introduced."
  (let ((checks nil)
        (bindings nil))
    (labels ((gen-elt (x)
               (cond
                ((%pcase--comma-form-p x)
                 (let ((p (cadr x)))
                   (cond
                    ((%pcase--dontcare-p p) (gensym "_"))
                    ((symbolp p) (pushnew p bindings :test #'eq) p)
                    (t
                     (let ((g (gensym "PCASE-")))
                       (push `(elisp:equal ,g ',p) checks)
                       g)))))
                ((%pcase--comma-at-form-p x)
                 (let ((p (cadr x)))
                   (cond
                    ((%pcase--dontcare-p p) '&rest)
                    ((symbolp p) (pushnew p bindings :test #'eq) (list '&rest p))
                    (t
                     (let ((g (gensym "REST-")))
                       (push `(elisp:equal ,g ',p) checks)
                       (list '&rest g))))))
                ((consp x)
                 ;; Dotted cdr patterns in backquote templates (e.g.
                 ;; `(and ,first . ,rest)) are read by Lisp as a proper list
                 ;; whose tail is the unquote operator and its operand:
                 ;;   (AND (\, FIRST) \\, REST)
                 ;; Recognize that suffix and translate it into a dotted
                 ;; destructuring lambda list: (AND FIRST . REST).
                 (let* ((proper-len (list-length x)))
                   (when (and proper-len (>= proper-len 2))
                     (let* ((tail2 (last x 2))
                            (marker (first tail2))
                            (pat (second tail2)))
                       (when (and (symbolp marker)
                                  (or (string= (symbol-name marker) ",")
                                      (string= (symbol-name marker) ",@")))
                         (let* ((prefix (butlast x 2))
                                (prefix-ll (mapcar #'gen-elt prefix))
                                (tail-ll
                                  (cond
                                   ((%pcase--dontcare-p pat) (gensym "_"))
                                   ((symbolp pat) (pushnew pat bindings :test #'eq) pat)
                                   (t
                                    (let ((g (gensym "PCASE-TAIL-")))
                                      (push `(elisp:equal ,g ',pat) checks)
                                      g))))
                                (ll (if (null prefix-ll)
                                        tail-ll
                                        (reduce (lambda (acc elt) (cons elt acc))
                                                (reverse prefix-ll)
                                                :initial-value tail-ll))))
                           (return-from gen-elt ll))))))
                 (let ((car (gen-elt (car x)))
                       (cdr (gen-elt (cdr x))))
                   (cond
                    ((and (consp car) (eq (car car) '&rest))
                     (cl:error "pcase: ,@ only supported in list tail position"))
                    ((and (consp cdr) (eq (car cdr) '&rest))
                     (cons car cdr))
                    (t (cons car cdr)))))
                ((null x) nil)
                ((vectorp x)
                 ;; Basic vector destructuring: translate to a list of elements.
                 (let ((lst (map 'list #'identity x)))
                   (coerce (mapcar #'gen-elt lst) 'vector)))
                (t
                 (let ((g (gensym "K-")))
                   (push `(elisp:equal ,g ',x) checks)
                   g)))))
      (let ((ll (gen-elt tmpl)))
        (cl:values ll (nreverse checks) (nreverse bindings))))))

(cl:defmacro pcase-let* (bindings &rest body)
  "Bring-up subset of ELisp `pcase-let*'.

Supports destructuring patterns of the form:
- SYMBOL (binds the whole value)
- `_`/`t` (don't care)
- backquote templates using `\, and `\,@ (from the ELisp reader)."
  (let ((forms body))
    (labels
        ((expand (bs)
           (if (null bs)
               `(progn ,@forms)
               (destructuring-bind (pat expr) (car bs)
                 (cond
                  ((%pcase--dontcare-p pat)
                   `(let ((,(gensym "_") ,expr))
                      ,(expand (cdr bs))))
                  ((symbolp pat)
                   `(let ((,pat ,expr))
                      ,(expand (cdr bs))))
                  ((%pcase--bq-form-p pat)
                   (let ((tmp (gensym "PCASE-VALUE-")))
                     (multiple-value-bind (ll checks _vars)
                         (%pcase--template->lambda-list (cadr pat))
                       (declare (cl:ignore _vars))
                       `(let ((,tmp ,expr))
                          (destructuring-bind ,ll ,tmp
                            (unless (and ,@checks)
                              (error "pcase-let*: pattern mismatch: %S %S" ',pat ,tmp))
                            ,(expand (cdr bs)))))))
                  (t
                   (cl:error "pcase-let*: unsupported pattern: ~S" pat)))))))
      (expand bindings))))

(cl:defmacro pcase-let (bindings &rest body)
  "Bring-up subset of ELisp `pcase-let'."
  `(pcase-let* ,bindings ,@body))

(cl:defmacro pcase-dolist (spec &rest body)
  "Bring-up subset of ELisp `pcase-dolist'."
  (destructuring-bind (pat listform) spec
    (if (%pcase--dontcare-p pat)
        `(dolist (_ ,listform) ,@body)
      (let ((tmp (gensym "PCASE-ELT-")))
        `(dolist (,tmp ,listform)
           (pcase-let* ((,pat ,tmp))
             ,@body))))))

(cl:defmacro defgroup (name _parents _docstring &rest _args)
  "Stub for ELisp `defgroup'."
  (declare (cl:ignore _parents _docstring _args))
  `(progn ',name))

(cl:defmacro defcustom (symbol value _docstring &rest _args)
  "Stub for ELisp `defcustom'."
  (declare (cl:ignore _docstring _args))
  `(defparameter ,symbol ,value))

(cl:defmacro defface (face _spec _docstring &rest _args)
  "Stub for ELisp `defface'."
  (declare (cl:ignore _spec _docstring _args))
  `(progn ',face))

(cl:defmacro define-globalized-minor-mode (global-mode mode turn-on &rest args)
  "Bring-up stub for ELisp `define-globalized-minor-mode'.

This defines GLOBAL-MODE as a global minor mode toggler.  During bring-up we
don't yet walk buffers or manage mode hooks, but we do define the variable and
command so preloaded startup files can be checkpointed."
  (declare (cl:ignore mode turn-on))
  (let ((init-value nil))
    (loop for (k v) on args by #'cddr do
      (when (eq k :init-value)
        (setf init-value v)))
    `(progn
       (defvar ,global-mode ,init-value)
       (defun ,global-mode (&optional arg)
         (declare (cl:ignore arg))
         (setf ,global-mode (not (not ,global-mode)))
         ,global-mode)
       ',global-mode)))

(cl:defun define-error (name message &optional parent)
  "Bring-up subset of ELisp `define-error'.

Records enough symbol properties for upstream ERT's `should-error':
- `error-message'
- `error-conditions' (a list of symbols, rooted at `error')."
  (unless (symbolp name)
    (cl:error "ELISP:DEFINE-ERROR expected symbol NAME, got: ~S" name))
  (unless (stringp message)
    (cl:error "ELISP:DEFINE-ERROR expected string MESSAGE, got: ~S" message))
  (unless (or (null parent) (symbolp parent))
    (cl:error "ELISP:DEFINE-ERROR expected symbol PARENT or nil, got: ~S" parent))
  (let* ((parent (or parent 'error))
         (parent-conds (get parent 'error-conditions)))
    (unless (and (listp parent-conds) (member parent parent-conds :test #'eq))
      ;; Seed `error' if it wasn't populated yet.
      (setf parent-conds (list parent))
      (setf (get parent 'error-conditions) parent-conds))
    (setf (get name 'error-message) message)
    (setf (get name 'error-conditions)
          (cons name parent-conds))
    name))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Emacs seeds these in C (data.c / Fsignal setup).  Upstream ELisp
  ;; `define-error' (in lisp/subr.el) assumes they already exist, and ERT's
  ;; `ert--should-error-handle-error' asserts it can read them.
  (flet ((seed (sym conds message)
           (unless (get sym 'error-conditions)
             (setf (get sym 'error-conditions) conds))
           (unless (get sym 'error-message)
             (setf (get sym 'error-message) message))))
    (seed 'error
          (list 'error)
          "Error")
    ;; Minimal arithmetic hierarchy used by upstream ERT tests.
    (seed 'arith-error
          (list 'arith-error 'error)
          "Arithmetic error")
    (seed 'domain-error
          (list 'domain-error 'arith-error 'error)
          "Arithmetic domain error")
    (seed 'singularity-error
          (list 'singularity-error 'domain-error 'arith-error 'error)
          "Arithmetic singularity error")
    (seed 'beginning-of-buffer
          (list 'beginning-of-buffer 'error)
          "Beginning of buffer")
    (seed 'end-of-buffer
          (list 'end-of-buffer 'error)
          "End of buffer")))

(cl:defmacro cl-assert (form &rest _args)
  "Bring-up subset of cl-lib's `cl-assert'.

Upstream ELisp often passes extra arguments (e.g. SHOW-ARGS, message
formatting). We currently ignore them and delegate to CL:ASSERT on FORM."
  (declare (cl:ignore _args))
  `(cl:assert ,form))

(cl:defmacro cl-defmacro (name lambda-list &body body)
  "Minimal subset of cl-lib's `cl-defmacro'."
  `(defmacro ,name ,lambda-list ,@body))

(cl:defmacro cl-defun (name lambda-list &body body)
  "Minimal subset of cl-lib's `cl-defun'."
  `(defun ,name ,lambda-list ,@body))

(cl:defmacro cl-destructuring-bind (lambda-list expr &body body)
  "Minimal subset of cl-lib's `cl-destructuring-bind'."
  `(cl:destructuring-bind ,lambda-list ,expr ,@body))

(cl:defun cl-plusp (x)
  "Bring-up subset of cl-lib's `cl-plusp'."
  (and (numberp x) (> x 0)))

(cl:defmacro cl-macrolet (bindings &body body &environment env0)
  "Bring-up subset of cl-lib's `cl-macrolet'.

ERT's `should' macro calls `macroexpand-all' and passes
`macroexpand-all-environment'.  In Emacs, `cl-macrolet' extends that
environment with its locally-bound macros.

In CL, the body is macroexpanded/compiled before any runtime LET bindings
exist, so we do the binding at macroexpansion time and pre-expand BODY under
an augmented SBCL lexical environment."
  (labels
      ((normalize-lambda-list (lambda-list)
         (labels ((rw (xs)
                    (cond
                     ((null xs) nil)
                     ((and (consp xs) (eq (car xs) '&body))
                      (cons '&rest (rw (cdr xs))))
                     (t (cons (car xs) (rw (cdr xs)))))))
           (rw lambda-list)))
       (strip-environment (lambda-list)
         (let ((out nil)
               (env-var nil))
           (loop while lambda-list do
             (let ((x (pop lambda-list)))
               (cond
                ((eq x '&environment)
                 (setf env-var (pop lambda-list)))
                (t
                 (push x out)))))
           (cl:values (nreverse out) env-var)))
       (binding->macro (binding)
         (destructuring-bind (name lambda-list &rest mbody) binding
           (let* ((lambda-list (normalize-lambda-list lambda-list)))
             (multiple-value-bind (lambda-list env-var)
                 (strip-environment lambda-list)
               (let ((body-form (if env-var
                                    `(let ((,env-var env)) (progn ,@mbody))
                                    `(progn ,@mbody))))
                 (list name
                       (cl:eval
                        `(lambda (form env)
                           (declare (ignorable form env))
                           (let ((args (cdr form)))
                             (declare (ignorable args))
                             (destructuring-bind ,lambda-list args
                               ,body-form)))))))))))
    (let* ((macro-defs (mapcar #'binding->macro bindings))
           (env1 (sb-cltl2:augment-environment env0 :macro macro-defs)))
      (let ((macroexpand-all-environment env1))
        (declare (special macroexpand-all-environment))
        ;; Keep expansion shallow: we only need to macroexpand top-level forms
        ;; so ERT's `should' macro sees `macroexpand-all-environment'.  A deep
        ;; walker can easily break code that relies on backquote internals.
        (let ((expanded-body (mapcar (lambda (f) (cl:macroexpand f env1)) body)))
          `(progn ,@expanded-body))))))

(cl:defmacro cl-flet (bindings &body body)
  "Minimal subset of cl-lib's `cl-flet'."
  `(cl:flet ,bindings ,@body))

(cl:defmacro cl-labels (bindings &body body)
  "Minimal subset of cl-lib's `cl-labels'."
  `(cl:labels ,bindings ,@body))

(cl:defmacro cl-loop (&rest clauses)
  "Minimal subset of cl-lib's `cl-loop'."
  (labels ((rewrite-by (x)
             (if (and (consp x) (eq (car x) 'function) (= (length x) 2))
                 (let ((arg (cadr x)))
                   (cond
                    ((symbolp arg) `(cl:function ,arg))
                    ((and (consp arg) (eq (car arg) 'lambda)) `(cl:function ,arg))
                    (t x)))
                 x))
           (rewrite-across (xs)
             ;; cl-lib's `cl-loop' iterates strings by character codes
             ;; (because `aref' returns integers).  CL:LOOP iterates strings
             ;; by CL characters, which breaks a number of upstream helpers
             ;; (notably ERT explainers).  Rewrite:
             ;;   for VAR across SEQ
             ;; into:
             ;;   for SEQG = SEQ then SEQG
             ;;   for IG from 0 below (length SEQG)
             ;;   for VAR = (aref SEQG IG)
             (let ((out nil)
                   (bindings nil)
                   (rest xs))
               (loop while rest do
                 (cond
                  ((and (consp rest)
                        (member (car rest) '(for as) :test #'eq)
                        (consp (cdr rest))
                        (symbolp (cadr rest))
                        (consp (cddr rest))
                        (eq (caddr rest) 'across)
                        (consp (cdddr rest)))
                   (let* ((kw (car rest))
                          (var (cadr rest))
                          (seq (cadddr rest))
                          (seqg (gensym "SEQ"))
                          (ig (gensym "I")))
                     (declare (cl:ignore kw))
                     (push (list seqg seq) bindings)
                     (setf rest (cddddr rest))
                     ;; OUT is built in reverse order.
                     (dolist (x (list 'for ig 'from 0 'below `(length ,seqg)
                                      'for var '= `(aref ,seqg ,ig)))
                       (push x out))))
                  (t
                   (push (car rest) out)
                   (setf rest (cdr rest)))))
               (cl:values (nreverse bindings) (nreverse out))))
           (walk (xs)
             (cond
              ((null xs) nil)
              ((eq (car xs) 'by)
               (cons 'by (cons (rewrite-by (cadr xs)) (walk (cddr xs)))))
              (t (cons (car xs) (walk (cdr xs)))))))
    (multiple-value-bind (bindings clauses*)
        (rewrite-across clauses)
      (if (null bindings)
          `(cl:loop ,@(walk clauses*))
          `(cl:let ,bindings
             (cl:loop ,@(walk clauses*)))))))

(cl:defmacro cl-etypecase (keyform &rest clauses)
  "Bring-up subset of cl-lib's `cl-etypecase'."
  `(cl:etypecase ,keyform ,@clauses))

(cl:defun cl-typep (object type)
  "Bring-up subset of cl-lib's `cl-typep'."
  (cond
   ((and (consp type) (eq (car type) 'satisfies) (= (length type) 2))
    (funcall (cadr type) object))
   (t
    (typep object type))))

(cl:defmacro cl-check-type (form type &optional _string)
  "Bring-up subset of cl-lib's `cl-check-type'."
  (declare (cl:ignore _string))
  (let ((tmp (gensym "VAL")))
    `(let ((,tmp ,form))
       (unless (cl-typep ,tmp ',type)
         (error "Wrong type: expected %S, got %S" ',type ,tmp))
       nil)))

(cl:defmacro cl-incf (place &optional (delta 1))
  "Minimal subset of cl-lib's `cl-incf'."
  `(cl:incf ,place ,delta))

(cl:defmacro cl-return (&optional value)
  "Minimal subset of cl-lib's `cl-return'."
  `(cl:return ,value))

(cl:defmacro cl-return-from (name &optional value)
  "Minimal subset of cl-lib's `cl-return-from'."
  `(cl:return-from ,name ,value))

(cl:defmacro cl-block (name &body body)
  "Minimal subset of cl-lib's `cl-block'."
  `(cl:block ,name ,@body))

(cl:defmacro cl-case (keyform &rest clauses)
  "Minimal subset of cl-lib's `cl-case'."
  `(cl:case ,keyform ,@clauses))

(cl:defmacro cl-ecase (keyform &rest clauses)
  "Minimal subset of cl-lib's `cl-ecase'."
  `(cl:ecase ,keyform ,@clauses))

(cl:defun cl-struct-p (_x)
  "Bring-up stub for cl-lib's `cl-struct-p'."
  (declare (cl:ignore _x))
  nil)

(cl:defun cl-intersection (list1 list2 &rest args &key (test 'eql) key &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-intersection'."
  (declare (cl:ignore args))
  (let ((test-fn
          (cond
           ((or (eq test 'eq) (eq test 'cl:eq)) #'cl:eq)
           ((or (eq test 'eql) (eq test 'cl:eql)) #'cl:eql)
           ((or (eq test 'equal) (eq test 'cl:equal)) #'cl:equalp)
           ((or (eq test 'equalp) (eq test 'cl:equalp)) #'cl:equalp)
           ((functionp test) test)
           (t (cl:error "ELISP:CL-INTERSECTION unsupported :test: ~S" test)))))
    (cl:intersection list1 list2 :test test-fn :key key)))

(cl:defun cl-set-difference (list1 list2 &rest args &key (test 'eql) key &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-set-difference'."
  (declare (cl:ignore args))
  (let ((test-fn
          (cond
           ((or (eq test 'eq) (eq test 'cl:eq)) #'cl:eq)
           ((or (eq test 'eql) (eq test 'cl:eql)) #'cl:eql)
           ((or (eq test 'equal) (eq test 'cl:equal)) #'cl:equalp)
           ((or (eq test 'equalp) (eq test 'cl:equalp)) #'cl:equalp)
           ((functionp test) test)
           (t (cl:error "ELISP:CL-SET-DIFFERENCE unsupported :test: ~S" test)))))
    (cl:set-difference list1 list2 :test test-fn :key key)))

(cl:defun cl-union (list1 list2 &rest args &key (test 'eql) key &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-union'."
  (declare (cl:ignore args))
  (let ((test-fn
          (cond
           ((or (eq test 'eq) (eq test 'cl:eq)) #'cl:eq)
           ((or (eq test 'eql) (eq test 'cl:eql)) #'cl:eql)
           ((or (eq test 'equal) (eq test 'cl:equal)) #'cl:equalp)
           ((or (eq test 'equalp) (eq test 'cl:equalp)) #'cl:equalp)
           ((functionp test) test)
           (t (cl:error "ELISP:CL-UNION unsupported :test: ~S" test)))))
    (cl:union list1 list2 :test test-fn :key key)))

(cl:defun cl-remove-if-not (predicate sequence &rest args &key &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-remove-if-not'."
  (apply #'cl:remove-if-not predicate sequence args))

(cl:defun cl-position (item sequence &rest args)
  "Bring-up subset of cl-lib's `cl-position'."
  (let* ((item (if (and (integerp item)
                        (stringp sequence)
                        ;; Only remap integer ITEM to a character when
                        ;; SEQUENCE is a multibyte (CL) string. Unibyte strings
                        ;; are byte vectors whose elements are integers.
                        (not (unibyte-string-p sequence)))
                   (or (code-char item) item)
                   item))
         (test (getf args :test 'eql))
         (test-fn
           (cond
            ((or (eq test 'eq) (eq test 'cl:eq)) #'cl:eq)
            ((or (eq test 'eql) (eq test 'cl:eql)) #'cl:eql)
            ((or (eq test 'equal) (eq test 'cl:equal)) #'cl:equalp)
            ((or (eq test 'equalp) (eq test 'cl:equalp)) #'cl:equalp)
            ((functionp test) test)
            (t (cl:error "ELISP:CL-POSITION unsupported :test: ~S" test))))
         (remapped-args
           (loop for (k v) on args by (cl:function cl:cddr)
                 collect k
                 collect (if (eq k :test) test-fn v))))
    (apply #'cl:position item sequence remapped-args)))

(cl:defun cl-gensym (&optional prefix)
  "Bring-up subset of cl-lib's `cl-gensym'."
  (let ((p (cond
            ((null prefix) "G")
            ((stringp prefix) prefix)
            ((symbolp prefix) (symbol-name prefix))
            (t (cl:error "ELISP:CL-GENSYM unsupported prefix: ~S" prefix)))))
    (gensym (string-upcase (%elisp-string->cl-string p)))))

(cl:defun cl-coerce (object type)
  "Bring-up subset of cl-lib's `cl-coerce'.

ELisp tends to pass type names as ELISP package symbols (e.g. `list'),
whereas CL:COERCE expects CL type names."
  (let ((type (if (symbolp type)
                 (intern (string-upcase (%elisp-string->cl-string (symbol-name type)))
                         (find-package "CL"))
                  type)))
    (coerce object type)))

(cl:defun cl-search (sequence1 sequence2 &rest args &key (test 'eql) &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-search'."
  (declare (cl:ignore args))
  (let ((test-fn
          (cond
           ((or (eq test 'eq) (eq test 'cl:eq)) #'cl:eq)
           ((or (eq test 'eql) (eq test 'cl:eql)) #'cl:eql)
           ((or (eq test 'equal) (eq test 'cl:equal)) #'cl:equalp)
           ((or (eq test 'equalp) (eq test 'cl:equalp)) #'cl:equalp)
           ((functionp test) test)
           (t (cl:error "ELISP:CL-SEARCH unsupported :test: ~S" test)))))
    (cl:search sequence1 sequence2 :test test-fn)))

(cl:defun cl-mismatch (sequence1 sequence2 &rest args &key (test 'eql) &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-mismatch'."
  (declare (cl:ignore args))
  (let ((test-fn
          (cond
           ((or (eq test 'eq) (eq test 'cl:eq)) #'cl:eq)
           ((or (eq test 'eql) (eq test 'cl:eql)) #'cl:eql)
           ((or (eq test 'equal) (eq test 'cl:equal)) #'cl:equalp)
           ((or (eq test 'equalp) (eq test 'cl:equalp)) #'cl:equalp)
           ((functionp test) test)
           (t (cl:error "ELISP:CL-MISMATCH unsupported :test: ~S" test)))))
    (cl:mismatch sequence1 sequence2 :test test-fn)))

(cl:defun cl-remprop (symbol indicator)
  "Minimal subset of cl-lib's `cl-remprop'."
  (and (remprop symbol indicator) t))

(cl:defmacro cl-letf* (bindings &body body)
  "Bring-up subset of cl-lib's `cl-letf*'.

This is intentionally narrow: it supports the temporary rebinding patterns
we hit in upstream ERT bring-up (e.g. rebinding `(symbol-function 'message)`).
Unsupported places error with a clear message."
  (labels
      ((expand (bs)
         (if (null bs)
             `(progn ,@body)
             (destructuring-bind (place expr) (car bs)
               (cond
                ;; cl-letf* allows plain variable bindings.
                ((symbolp place)
                 `(let ((,place ,expr))
                    ,(expand (cdr bs))))
                ;; Limited generalized variable support.
                ((and (consp place) (eq (car place) 'symbol-function) (= (length place) 2))
                 (let ((sym (gensym "SYM"))
                       (old (gensym "OLD"))
                       (new (gensym "NEW")))
                   `(let* ((,sym ,(cadr place))
                           (,old (symbol-function ,sym))
                           (,new ,expr))
                      (unwind-protect
                          (progn
                            (fset ,sym ,new)
                            ,(expand (cdr bs)))
                        (fset ,sym ,old)))))
                ((and (consp place) (eq (car place) 'symbol-value) (= (length place) 2))
                 (let ((sym (gensym "SYM"))
                       (old (gensym "OLD"))
                       (new (gensym "NEW")))
                   `(let* ((,sym ,(cadr place))
                           (,old (symbol-value ,sym))
                           (,new ,expr))
                      (unwind-protect
                          (progn
                            (set ,sym ,new)
                            ,(expand (cdr bs)))
                        (set ,sym ,old)))))
                (t
                 (cl:error "ELISP:CL-LETF* unsupported place: ~S" place)))))))
    (expand bindings)))

(cl:defparameter cl--lambda-list-keywords
  '(&optional &rest &key &allow-other-keys &aux &whole &body &environment &form
    &cl-defs)
  "Bring-up subset of cl-lib's internal `cl--lambda-list-keywords'.")

(cl:defun cl--arglist-args (lambda-list)
  "Bring-up subset of cl-lib's internal `cl--arglist-args'.

Returns a list of argument variable symbols from LAMBDA-LIST."
  (let ((out nil)
        (rest lambda-list))
    (loop while rest do
      (let ((x (pop rest)))
        (cond
         ((memq x cl--lambda-list-keywords)
          nil)
         ((symbolp x)
          (push x out))
         ((consp x)
          (let ((name (car x)))
            (when (symbolp name)
              (push name out))))
         (t nil))))
    (nreverse out)))

(cl:defun cl--find-class (name)
  "Bring-up stub for cl-lib's internal `cl--find-class'."
  (and (symbolp name) (get name 'cl--class)))

(cl:defsetf cl--find-class (name) (value)
  `(progn
     (put ,name 'cl--class ,value)
     ,value))

(cl:defun cl--make-slot-descriptor (name &optional initform type props)
  "Bring-up subset of cl-lib's internal `cl--make-slot-descriptor'.

This is used by `oclosure.el` when building its lightweight type objects.
We represent slot descriptors using the (ported) `cl-slot-descriptor' CL struct
defined in `lisp/emacs-lisp/cl-preloaded.el`."
  (make-cl-slot-descriptor :name name :initform initform :type type :props props))

(cl:defmacro cl-deftype (name args &body body)
  "Bring-up subset of cl-lib's `cl-deftype'.

This is a thin wrapper over CL:DEFTYPE so ELisp libraries that use cl-lib's
type specifiers (e.g. `oclosure.el`) can load without needing the full cl-lib
macro suite."
  `(cl:deftype ,name ,args ,@body))

(cl:defmacro cl-defstruct (&rest args)
  "Minimal subset of cl-lib's `cl-defstruct'.

Upstream cl-lib defaults to `make-<name>' constructors, like CL:DEFSTRUCT.
We only special-case SBCL quirks around (:constructor nil) combined with
named constructors."
  (let* ((spec (car args))
         (rest (cdr args))
         (doc (and rest (stringp (car rest)) (pop rest)))
         (doc* (and doc (if (cl:stringp doc) doc (%elisp-string->cl-string doc))))
         (name (if (consp spec) (car spec) spec))
         (opts (and (consp spec) (cdr spec)))
         (ctor-opts (remove-if-not (lambda (x) (and (consp x) (eq (car x) :constructor))) opts))
         (ctor-nil-p (and ctor-opts
                          (some (lambda (x) (null (cadr x))) ctor-opts)))
         (ctors (remove nil (mapcar #'cadr ctor-opts)))
         (opts* (if (and ctor-nil-p ctors)
                    ;; SBCL rejects (:constructor nil) combined with other
                    ;; constructors; cl-lib uses this to disable the default
                    ;; constructor while still defining named constructors.
                    (remove-if (lambda (x)
                                 (and (consp x) (eq (car x) :constructor) (null (cadr x))))
                               opts)
                    opts))
         (spec* (if (consp spec) (cons name opts*) spec))
         (slots*
           (mapcar
            (lambda (slot)
              ;; cl-lib sometimes includes :documentation in slot plists;
              ;; CL:DEFSTRUCT doesn't accept it, so drop it.
              (cond
               ((symbolp slot) slot)
               ((consp slot)
                (let ((nm (car slot))
                      (init (cadr slot))
                      (plist (cddr slot)))
                  (list* nm init
                         (loop for (k v) on plist by #'cddr
                               unless (eq k :documentation)
                                 append (list k v)))))
               (t slot)))
            rest))
         (args* (append (list spec*)
                        (when doc* (list doc*))
                        slots*)))
    (declare (cl:ignore name))
    `(cl:defstruct ,@args*)))

(cl:defmacro cl-defgeneric (name args &rest rest)
  "Bring-up subset of cl-generic's `cl-defgeneric'.

Defines a CLOS generic function, and (when BODY is provided) a default method."
  (unless (and (symbolp name) (listp args))
    (cl:error "ELISP:CL-DEFGENERIC expects (NAME ARGS ...), got: ~S ~S" name args))
  (let* ((doc (and rest (stringp (car rest)) (pop rest)))
         (body rest)
         (method-args
           (loop for a in args
                 while (and (symbolp a)
                            (not (keywordp a))
                            (let ((nm (symbol-name a)))
                              (or (zerop (length nm))
                                  (/= (aref nm 0) (char-code #\&)))))
                 collect `(,a t))))
    `(progn
       (cl:defgeneric ,name ,args
         ,@(when doc `((:documentation ,doc))))
       ,@(when body
           `((cl:defmethod ,name ,method-args
               ,@body)))
       ',name)))

(cl:defmacro cl-defmethod (name args &rest body)
  "Bring-up subset of cl-generic's `cl-defmethod'."
  (unless (and (listp args) (not (null args)))
    (cl:error "ELISP:CL-DEFMETHOD expects (NAME ARGS ...), got: ~S ~S" name args))
  (labels ((normalize-class-specializer (spec)
             ;; We shadow ELISP::STRING as a function, but ELisp cl-generic uses
             ;; the symbol `string' as a type specializer.  Rewrite to the CL
             ;; class so the underlying CLOS dispatch works.
             (cond
              ((eq spec 'string) 'cl:string)
              ((eq spec 'marker) 'elisp-marker)
              ((eq spec 'window-configuration) 'elisp-window-configuration)
              (t spec))))
    (let* ((saw-string-specializer nil)
           (method-args
             (mapcar
              (lambda (a)
                (cond
                 ((symbolp a) a)
                 ((and (consp a) (= (length a) 2) (symbolp (car a)))
                  (let ((var (car a))
                        (spec (cadr a)))
                    ;; Emacs's cl-generic treats (eql SOME-SYMBOL) as an EQL
                    ;; specializer on the symbol itself (i.e. effectively
                    ;; (eql 'SOME-SYMBOL)), not as a variable reference.
                    (cond
                     ((and (consp spec)
                           (eq (car spec) 'eql)
                           (consp (cdr spec))
                           (null (cddr spec))
                           (symbolp (cadr spec)))
                      (list var (list 'eql (list 'quote (cadr spec)))))
                     ((symbolp spec)
                      (when (eq spec 'string)
                        (setf saw-string-specializer t))
                      (list var (normalize-class-specializer spec)))
                     (t a))))
                 (t (cl:error "ELISP:CL-DEFMETHOD unsupported arg spec: ~S" a))))
              args)))
      ;; ELisp `string' specializers must match both CL strings (multibyte) and
      ;; our unibyte string representation (a specialized (unsigned-byte 8)
      ;; vector).  For the common 1-arg case, emit a second method to catch
      ;; unibyte strings.
      (if (and saw-string-specializer
               (= (length method-args) 1)
               (consp (car method-args))
               (eq (cadar method-args) 'cl:string))
          (let ((var (caar method-args)))
            `(progn
               (cl:defmethod ,name ((,var cl:string)) ,@body)
               (cl:defmethod ,name ((,var cl:vector))
                 (if (unibyte-string-p ,var)
                     (progn ,@body)
                     (call-next-method)))))
          `(cl:defmethod ,name ,method-args
             ,@body)))))

(cl:defun put (symbol prop value)
  "ELisp-ish PUT for symbol plists."
  (setf (get symbol prop) value)
  value)

(cl:defun getenv (var)
  "Bring-up subset of ELisp `getenv'."
  (unless (stringp var)
    (error "ELISP:GETENV expects a string, got: ~S" var))
  (uiop:getenv (%elisp-string->cl-string var)))

(cl:defvar user-emacs-directory
  (namestring (merge-pathnames ".emacs.d/" (user-homedir-pathname))))

(cl:defun locate-user-emacs-file (new-name &optional _old-name)
  "Bring-up subset of ELisp `locate-user-emacs-file'."
  (declare (cl:ignore _old-name))
  (unless (stringp new-name)
    (error "ELISP:LOCATE-USER-EMACS-FILE expects string, got: ~S" new-name))
  (let* ((path (namestring
                (merge-pathnames (%elisp-string->cl-string new-name)
                                 user-emacs-directory))))
    ;; Emacs returns unibyte strings for ASCII-only file names.
    (if (every (lambda (ch) (< (char-code ch) 128)) path)
        (string-to-unibyte path)
        path)))

(cl:defun make-list (length init)
  "ELisp-ish MAKE-LIST."
  (unless (and (integerp length) (>= length 0))
    (error "ELISP:MAKE-LIST expects nonnegative integer length, got: ~S" length))
  (cl:make-list length :initial-element init))

(cl:defun make-string (length init)
  "ELisp-ish `make-string'.

LENGTH is the string length. INIT is an ELisp character code or a CL character."
  (unless (and (integerp length) (>= length 0))
    (error "ELISP:MAKE-STRING expects nonnegative integer length, got: ~S" length))
  (let ((code (typecase init
                (integer init)
                (character (char-code init))
                (t (error "ELISP:MAKE-STRING expects char code or character, got: ~S" init)))))
    ;; Emacs returns unibyte strings for ASCII-only output, and multibyte once
    ;; non-ASCII or raw-byte codes appear.
    (if (and (integerp code) (<= 0 code 127))
        (%make-unibyte-string length :initial-element code)
        (let ((ch (%elisp-code->char code)))
          (cl:make-string length :initial-element ch)))))

(defvar *charset-aliases* (cl:make-hash-table :test 'eq))

(cl:defvar char-code-property-alist nil)

(cl:defun define-char-code-property (name file docstring)
  "Bring-up stub for ELisp `define-char-code-property'.

Record NAME as a known char-code property, and remember its data FILE and
DOCSTRING.  The actual property tables are loaded lazily by upstream code; for
bring-up we only need registration to succeed so `international/charprop.el'
can be loaded."
  (unless (symbolp name)
    (error "ELISP:DEFINE-CHAR-CODE-PROPERTY expects a symbol, got: ~S" name))
  (unless (stringp file)
    (error "ELISP:DEFINE-CHAR-CODE-PROPERTY expects a string file, got: ~S" file))
  (unless (stringp docstring)
    (error "ELISP:DEFINE-CHAR-CODE-PROPERTY expects a docstring, got: ~S" docstring))
  (put name 'char-code-property t)
  (put name 'char-code-property-file file)
  (put name 'char-code-property-doc docstring)
  (unless (assq name char-code-property-alist)
    (push (cons name nil) char-code-property-alist))
  name)

(cl:defvar *defined-categories* (cl:make-hash-table :test 'eql))

(cl:defun define-category (category docstring)
  "Bring-up stub for ELisp `define-category'.

Emacs uses category tables for syntax/category classification of characters.
For bring-up we only record the category definitions so that
`international/characters.el` can be loaded."
  (unless (integerp category)
    (error "ELISP:DEFINE-CATEGORY expects a character code integer, got: ~S" category))
  (unless (stringp docstring)
    (error "ELISP:DEFINE-CATEGORY expects a docstring, got: ~S" docstring))
  (setf (gethash category *defined-categories*) docstring)
  category)

(cl:defun define-charset-alias (alias charset)
  "Bring-up stub for ELisp `define-charset-alias'."
  (unless (and (symbolp alias) (symbolp charset))
    (error "ELISP:DEFINE-CHARSET-ALIAS expects symbols, got: ~S ~S" alias charset))
  (setf (gethash alias *charset-aliases*) charset)
  alias)

(cl:defun %resolve-charset (sym &key (max-hops 16))
  (loop with cur = sym
        for hop from 0 below max-hops do
          (multiple-value-bind (next presentp)
              (gethash cur *charset-aliases*)
            (cond
             ((not presentp) (return cur))
             ((not (symbolp next)) (return cur))
             (t (setf cur next))))
        finally
          (return sym)))

(cl:defun charset-plist (charset)
  "Bring-up subset of the C primitive `charset-plist'."
  (unless (symbolp charset)
    (error "ELISP:CHARSET-PLIST expects a symbol, got: ~S" charset))
  (symbol-plist (%resolve-charset charset)))

(cl:defun set-charset-plist (charset plist)
  "Bring-up subset of the internal helper `set-charset-plist'."
  (unless (symbolp charset)
    (error "ELISP:SET-CHARSET-PLIST expects a symbol, got: ~S" charset))
  (setf (symbol-plist (%resolve-charset charset)) plist)
  plist)

(cl:defun define-charset-internal (name &rest attrs)
  "Bring-up stub for the C primitive `define-charset-internal'."
  (unless (symbolp name)
    (error "ELISP:DEFINE-CHARSET-INTERNAL expects symbol, got: ~S" name))
  (let ((plist (car (last attrs))))
    (when (listp plist)
      (set-charset-plist name plist))
    (put name 'charsetp t)
    name))

(cl:defun put-charset-property (charset prop value)
  "Bring-up stub for ELisp `put-charset-property'."
  (unless (and (symbolp charset) (symbolp prop))
    (error "ELISP:PUT-CHARSET-PROPERTY expects symbols, got: ~S ~S" charset prop))
  (put (%resolve-charset charset) prop value))

(cl:defun unify-charset (charset)
  "Bring-up stub for the C primitive `unify-charset'."
  (unless (symbolp charset)
    (error "ELISP:UNIFY-CHARSET expects a symbol, got: ~S" charset))
  charset)

(cl:defun define-charset (name _docstring &rest plist)
  "Bring-up stub for ELisp `define-charset'.

We currently represent charsets as symbols with properties."
  (declare (cl:ignore _docstring))
  (unless (symbolp name)
    (error "ELISP:DEFINE-CHARSET expects symbol, got: ~S" name))
  (put name 'charsetp t)
  (when (cl:oddp (length plist))
    (error "ELISP:DEFINE-CHARSET odd keyword args: ~S" plist))
  (loop for (k v) on plist by (cl:function cl:cddr) do
    (put name k v))
  name)

(defstruct elisp-keymap
  (table (cl:make-hash-table :test 'cl:equal))
  (parent nil))

(defparameter system-type 'darwin)
(cl:defun system-name ()
  "Bring-up subset of ELisp `system-name'."
  (or (ignore-errors (uiop:hostname))
      (ignore-errors (machine-instance))
      "unknown"))

(cl:defun current-time ()
  "Bring-up subset of ELisp `current-time'.

  Returns an Emacs-style time value: (HI LO USEC PSEC), where seconds are encoded
  as HI*65536 + LO."
  (multiple-value-bind (sec usec) (sb-ext:get-time-of-day)
    (let ((hi (floor sec 65536))
          (lo (mod sec 65536)))
      (list hi lo usec 0))))

(cl:defun format-time-string (format &optional time _universal _zone)
  "Bring-up subset of ELisp `format-time-string'.

Supports the conversion specs needed by ERT: %Y %m %d %T %z."
  (declare (cl:ignore _universal _zone))
  (unless (stringp format)
    (error "ELISP:FORMAT-TIME-STRING expects string format, got: ~S" format))
  (labels ((time-seconds (tval)
             (cond
              ((null tval)
               (time-seconds (current-time)))
              ((and (consp tval)
                    (integerp (first tval))
                    (integerp (second tval)))
               (+ (* (first tval) 65536) (second tval)))
              ((integerp tval) tval)
              (t
               (error "ELISP:FORMAT-TIME-STRING unsupported time: ~S" tval))))
           (pad2 (n)
             (cl:format nil "~2,'0D" n))
           (pad4 (n)
             (cl:format nil "~4,'0D" n))
           (tz-offset (zone-west)
             ;; CL zone is hours west of UTC; ISO8601 expects offset east.
             (let* ((east (- zone-west))
                    (sign (if (minusp east) #\- #\+))
                    (abs (abs east))
                    (hh (floor abs))
                    (mm 0))
               (cl:format nil "~C~2,'0D~2,'0D" sign hh mm))))
    (let* ((sec (time-seconds time))
           ;; CL universal time is seconds since 1900-01-01 UTC.
           (ut (+ sec 2208988800))
           (ss 0) (mm 0) (hh 0) (dd 0) (mo 0) (yy 0) (dow 0) (dst 0) (zone 0))
      (declare (cl:ignore dow dst))
      (multiple-value-setq (ss mm hh dd mo yy dow dst zone)
        (decode-universal-time ut))
      (let* ((fmt (%elisp-string->cl-string format))
             (len (length fmt)))
        (with-output-to-string (out)
          (loop for i from 0 below len do
            (let ((ch (char fmt i)))
              (if (char= ch #\%)
                  (let ((next (and (< (1+ i) len) (char fmt (1+ i)))))
                    (unless next
                      (write-char ch out)
                      (return))
                    (incf i)
                    (case next
                      (#\Y (write-string (pad4 yy) out))
                      (#\m (write-string (pad2 mo) out))
                      (#\d (write-string (pad2 dd) out))
                      (#\T (write-string (cl:format nil "~2,'0D:~2,'0D:~2,'0D" hh mm ss) out))
                      (#\z (write-string (tz-offset zone) out))
                      (t
                       ;; Unknown spec: emit literally.
                       (write-char #\% out)
                       (write-char next out))))
                  (write-char ch out)))))))))

(cl:defun program-version ()
  "Bring-up subset of ELisp `program-version'."
  emacs-version)

(defparameter system-configuration
  (cl:format nil "~A-apple-darwin"
             (string-downcase (machine-type))))

(defvar *global-map* nil)
(defparameter minibuffer-local-map (make-elisp-keymap))
(defparameter find-function-space-re "")
(cl:defvar find-function-regexp-alist nil)
(defparameter buffer-file-name nil)
(cl:defvar fill-column 70)
(defparameter noninteractive t)
(defparameter current-load-list nil)
(cl:defvar load-history nil)
(cl:defvar after-load-alist nil)
(cl:defvar describe-symbol-backends nil)
(cl:defvar minor-mode-alist nil)
(cl:defvar help-char 8)
(cl:defvar font-lock-mode nil)

;; ---------------------------------------------------------------------------
;; Minimal buffer/marker surface (enough for upstream ERT bring-up)
;; ---------------------------------------------------------------------------

(defstruct elisp-marker-edit
  ;; :insert  a=at  b=len
  ;; :delete  a=start  b=end
  (kind :insert :type keyword)
  (a 0 :type integer)
  (b 0 :type integer))

(defstruct elisp-buffer
  (name "" :type (or cl:string unibyte-string))
  (text "" :type cl:string)
  (point 1 :type integer)
  (syntax-table nil)
  (locals (cl:make-hash-table :test 'eq) :type hash-table)
  ;; Weak registry of markers attached to this buffer (for edit-log compaction).
  (markers #+sbcl (make-hash-table :test 'eq :weakness :key)
           #-sbcl (make-hash-table :test 'eq)
           :type hash-table)
  (marker-edits (make-array 0 :adjustable t :fill-pointer 0) :type vector))

(defstruct elisp-marker
  (buffer nil)
  (position nil)
  ;; If true, the marker advances when text is inserted at its position.
  (insertion-type nil)
  ;; Number of buffer edits already applied to POSITION.
  (edit-index 0 :type integer))

(defparameter +marker-edit-compact-threshold+ 256)

(cl:defun %buffer-register-marker (buffer marker)
  (when (and (elisp-buffer-p buffer) (elisp-marker-p marker))
    (setf (gethash marker (elisp-buffer-markers buffer)) t))
  marker)

(cl:defun %buffer-unregister-marker (buffer marker)
  (when (and (elisp-buffer-p buffer) (elisp-marker-p marker))
    (remhash marker (elisp-buffer-markers buffer)))
  marker)

(cl:defun %buffer-maybe-compact-marker-edits (buffer)
  (let* ((edits (elisp-buffer-marker-edits buffer))
         (n (fill-pointer edits)))
    (when (> n +marker-edit-compact-threshold+)
      ;; Bring all live markers up-to-date, then clear the edit log.
      (maphash
       (lambda (m _)
         (declare (cl:ignore _))
         (%marker-sync m)
         (setf (elisp-marker-edit-index m) 0))
       (elisp-buffer-markers buffer))
      (setf (fill-pointer edits) 0)))
  nil)

(cl:defun %buffer-record-insert (buffer at len)
  (when (plusp len)
    (vector-push-extend (make-elisp-marker-edit :kind :insert :a at :b len)
                        (elisp-buffer-marker-edits buffer)))
  (%buffer-maybe-compact-marker-edits buffer)
  nil)

(cl:defun %buffer-record-delete (buffer start end)
  (let ((len (- end start)))
    (when (plusp len)
      (vector-push-extend (make-elisp-marker-edit :kind :delete :a start :b end)
                          (elisp-buffer-marker-edits buffer))))
  (%buffer-maybe-compact-marker-edits buffer)
  nil)

(cl:defun %marker-sync (marker)
  (let* ((buf (elisp-marker-buffer marker))
         (pos (elisp-marker-position marker)))
    (when (and (elisp-buffer-p buf) (integerp pos))
      (let* ((edits (elisp-buffer-marker-edits buf))
             (n (fill-pointer edits))
             (i (min (elisp-marker-edit-index marker) n)))
        (loop for idx from i below n do
          (let* ((e (aref edits idx))
                 (kind (elisp-marker-edit-kind e)))
            (ecase kind
              (:insert
               (let ((at (elisp-marker-edit-a e))
                     (len (elisp-marker-edit-b e)))
                 (when (or (> pos at)
                           (and (= pos at) (elisp-marker-insertion-type marker)))
                   (incf pos len))))
              (:delete
               (let ((start (elisp-marker-edit-a e))
                     (end (elisp-marker-edit-b e))
                     (len (- (elisp-marker-edit-b e) (elisp-marker-edit-a e))))
                 (cond
                  ((> pos end) (decf pos len))
                  ((>= pos start) (setf pos start)))))))
        ;; Keep marker positions within buffer bounds.  Emacs clamps positions,
        ;; and allowing markers to drift past point-max can lead to infinite
        ;; loops in code that uses an end-marker as a moving boundary (pp.el).
        (let ((pmax (1+ (length (elisp-buffer-text buf)))))
          (setf pos (max (point-min) (min pos pmax))))
        (setf (elisp-marker-position marker) pos
              (elisp-marker-edit-index marker) n))))
  marker))

(cl:defun %buffer-edit-index (buffer)
  (fill-pointer (elisp-buffer-marker-edits buffer)))

(cl:defun make-marker ()
  "Bring-up subset of ELisp `make-marker'.

Returns a marker with no buffer/position."
  (make-elisp-marker))

(cl:defun markerp (x)
  (elisp-marker-p x))

(cl:defun marker-position (marker)
  "Bring-up subset of ELisp `marker-position'."
  (unless (elisp-marker-p marker)
    (error "ELISP:MARKER-POSITION expected marker, got: ~S" marker))
  (elisp-marker-position (%marker-sync marker)))

(defvar *buffer-table* (cl:make-hash-table :test 'cl:equal))

(cl:defun %buffer-name-key (name)
  ;; Keep buffer table keys as CL strings so CL:EQUAL hashing works even when
  ;; ELisp passes us unibyte strings.
  (%elisp-string->cl-string name))

(cl:defun %register-buffer (buf)
  (setf (gethash (%buffer-name-key (elisp-buffer-name buf)) *buffer-table*) buf)
  buf)

(defvar *messages-buffer* (%register-buffer (make-elisp-buffer :name "*Messages*")))
(defvar *current-buffer* *messages-buffer*)
(defparameter message-log-max t)

(cl:defun current-buffer ()
  *current-buffer*)

(cl:defun bufferp (x)
  "Bring-up subset of ELisp `bufferp'."
  (elisp-buffer-p x))

(cl:defun messages-buffer ()
  *messages-buffer*)

;; ---------------------------------------------------------------------------
;; Syntax tables / indentation (minimal stubs for pp.el bring-up)
;; ---------------------------------------------------------------------------

(cl:defvar emacs-lisp-mode-syntax-table :emacs-lisp-mode-syntax-table)

(cl:defun syntax-table ()
  "Bring-up stub for ELisp `syntax-table'."
  (elisp-buffer-syntax-table *current-buffer*))

(cl:defun set-syntax-table (table)
  "Bring-up stub for ELisp `set-syntax-table'."
  (setf (elisp-buffer-syntax-table *current-buffer*) table)
  table)

(cl:defmacro with-syntax-table (table &body body)
  "Bring-up stub for ELisp `with-syntax-table'."
  (let ((old (cl:gensym "OLD-SYNTAX-TABLE-")))
    `(let ((,old (syntax-table)))
       (unwind-protect
           (progn
             (set-syntax-table ,table)
             ,@body)
         (set-syntax-table ,old)))))

(cl:defvar indent-line-function nil)

(cl:defun lisp-mode-variables (&optional _arg)
  "Bring-up stub for ELisp `lisp-mode-variables'."
  (declare (cl:ignore _arg))
  (setf indent-line-function #'lisp-indent-line)
  nil)

(cl:defun lisp-indent-line ()
  "Bring-up subset of ELisp `lisp-indent-line'.

This is a small indentation model sufficient for pp.el/ERT bring-up."
  (let* ((txt (elisp-buffer-text *current-buffer*))
         (idx (1- (point)))
         (nl (cl:position #\Newline txt :end idx :from-end t))
         (line-start (if nl (+ nl 2) (point-min)))
         (saved (point)))
    (labels ((ws-p (ch)
               (or (char= ch #\Space)
                   (char= ch #\Tab)
                   (char= ch #\Newline)
                   (char= ch #\Return)))
             (peek (p)
               (when (and (<= (point-min) p) (< p (point-max)))
                 (char (elisp-buffer-text *current-buffer*) (1- p))))
             (skip-ws (p &optional (limit (point-max)))
               (loop for pos = p then (1+ pos)
                     while (< pos limit)
                     for ch = (peek pos)
                     while (and ch (ws-p ch))
                     finally (return pos)))
             (column-at-pos (p)
               (let ((p0 (point)))
                 (unwind-protect
                     (progn (goto-char p) (current-column))
                   (goto-char p0))))
             (strip-indentation ()
               (goto-char line-start)
               (skip-chars-forward (coerce (list #\Space #\Tab) 'cl:string))
               (let ((nonws (point)))
                 (when (> nonws line-start)
                   (delete-region line-start nonws)
                   (let ((deleted (- nonws line-start)))
                     (setf saved
                           (cond
                            ((<= saved nonws) line-start)
                            (t (- saved deleted))))))))
             (indent-to (n)
               (strip-indentation)
               (goto-char line-start)
               (when (plusp n)
                 (insert (cl:make-string n :initial-element #\Space))
                 (when (>= saved line-start)
                   (incf saved n)))
               (goto-char (min (point-max) (max line-start saved))))
             (find-containing-open-paren (p)
               (let ((depth 0)
                     (open nil))
                 (loop for i downfrom (1- p) downto (point-min) do
                   (let ((ch (peek i)))
                     (cond
                      ((null ch) (return))
                      ((char= ch #\)) (incf depth))
                      ((char= ch #\() (if (zerop depth)
                                          (progn (setf open i) (return))
                                          (decf depth))))))
                 open))
             (line-leading-char ()
               (peek (skip-ws line-start)))
             (token-starts-with-colon-p (p)
               (let ((ch (peek p)))
                 (and ch (char= ch #\:)))))
      (let* ((open (find-containing-open-paren line-start))
             (indent-col 0))
        (cond
         ((null open)
          (setf indent-col 0))
         ((let ((ch (line-leading-char)))
            (and ch (char= ch #\))))
          (setf indent-col (column-at-pos open)))
         (t
          (let* ((open-col (column-at-pos open))
                 (head-start (skip-ws (1+ open) line-start)))
            (if (>= head-start line-start)
                (setf indent-col (1+ open-col))
                (let* ((head-end (or (scan-sexps head-start 1) head-start))
                       (arg1 (skip-ws head-end))
                       (head-sym
                         (when (and (< head-start line-start)
                                    (integerp head-end)
                                    (> head-end head-start))
                           (let ((token (subseq txt (1- head-start) (1- head-end))))
                             (ignore-errors (intern-soft token)))))
                       ;; Emacs distinguishes between function calls and "data
                       ;; lists": when the head symbol is not fboundp, indent
                       ;; like a plain list (open-col+1).  This matters for
                       ;; upstream ERT output (e.g. `ert-test-failed').
                       (head-fn-like-p (and head-sym (fboundp head-sym))))
                  (cond
                   ((or (null arg1) (>= arg1 (point-max)))
                    (setf indent-col (+ open-col 2)))
                   ((token-starts-with-colon-p head-start)
                    ;; Plist / keyword lists: indent continuation lines to the
                    ;; column of the first value, matching Emacs Lisp's
                    ;; `lisp-indent-line' behavior (pp.el relies on this).
                    (setf indent-col (column-at-pos arg1)))
                   ((>= arg1 line-start)
                    (setf indent-col (+ open-col (if head-fn-like-p 2 1))))
                   (t
                    (setf indent-col (column-at-pos arg1)))))))))
        (indent-to indent-col)
        nil))))

(cl:defun get-buffer (buffer-or-name)
  "Bring-up subset of ELisp `get-buffer'."
  (etypecase buffer-or-name
    (elisp-buffer buffer-or-name)
    ((or cl:string unibyte-string)
     (gethash (%buffer-name-key buffer-or-name) *buffer-table*))
    (null nil)))

(cl:defun get-buffer-create (name &optional _inhibit-buffer-hooks)
  "Bring-up subset of ELisp `get-buffer-create'."
  (declare (cl:ignore _inhibit-buffer-hooks))
  (unless (stringp name)
    (error "ELISP:GET-BUFFER-CREATE expects a string name, got: ~S" name))
  (or (gethash (%buffer-name-key name) *buffer-table*)
      (%register-buffer (make-elisp-buffer :name name))))

(cl:defun generate-new-buffer-name (name &optional _ignore)
  "Bring-up subset of ELisp `generate-new-buffer-name'."
  (declare (cl:ignore _ignore))
  (unless (stringp name)
    (error "ELISP:GENERATE-NEW-BUFFER-NAME expects a string, got: ~S" name))
  (if (null (gethash (%buffer-name-key name) *buffer-table*))
      name
      (loop for n from 2 do
        (let* ((base (%elisp-string->cl-string name))
               (cand (cl:format nil "~A<~D>" base n)))
          (when (null (gethash cand *buffer-table*))
            (return (string-to-unibyte cand)))))))

(cl:defun kill-buffer (buffer-or-name)
  "Bring-up subset of ELisp `kill-buffer'."
  (let ((buf (get-buffer buffer-or-name)))
    (unless buf
      (return-from kill-buffer nil))
    (remhash (%buffer-name-key (elisp-buffer-name buf)) *buffer-table*)
    (%clear-buffer-text-properties buf)
    (when (eq buf *current-buffer*)
      (setf *current-buffer* *messages-buffer*))
    t))

(cl:defun set-buffer (buffer-or-name)
  "Bring-up subset of ELisp `set-buffer'."
  (let ((buf (or (get-buffer buffer-or-name)
                 (and (stringp buffer-or-name)
                      (error "ELISP:SET-BUFFER no such buffer: ~S" buffer-or-name))
                 (error "ELISP:SET-BUFFER invalid buffer: ~S" buffer-or-name))))
    (setf *current-buffer* buf)
    buf))

(cl:defmacro with-current-buffer (buffer &body body)
  `(let ((*current-buffer* (or (get-buffer ,buffer) ,buffer)))
     ,@body))

(cl:defmacro with-temp-buffer (&body body)
  `(with-current-buffer (make-elisp-buffer :name " *temp*")
     ,@body))

(cl:defmacro save-current-buffer (&body body)
  `(let ((buf (current-buffer)))
     (unwind-protect
         (progn ,@body)
       (set-buffer buf))))

(cl:defmacro save-window-excursion (&body body)
  `(save-current-buffer ,@body))

(cl:defmacro save-excursion (&body body)
  "Bring-up subset of ELisp `save-excursion'."
  ;; Emacs restores point using a marker so buffer edits inside BODY don't
  ;; shift the restored position.  This matters for pp.el, which uses
  ;; `save-excursion' around insertions while scanning the same line.
  (let ((buf (cl:gensym "BUF-"))
        (pt (cl:gensym "PT-")))
    `(let* ((,buf (current-buffer))
            (,pt (point-marker)))
       (unwind-protect
           (progn ,@body)
         ;; Restore buffer and point (clamped by `goto-char'), then drop the
         ;; temporary marker so we don't accumulate marker registry entries.
         (set-buffer ,buf)
         (goto-char ,pt)
         (%buffer-unregister-marker ,buf ,pt)))))

(cl:defun prin1 (object &optional stream)
  "Bring-up subset of ELisp `prin1'.

STREAM may be a buffer."
  (let ((out (or stream (current-buffer))))
    (cond
     ((bufferp out)
      (with-current-buffer out
        (insert (prin1-to-string object))))
     ((streamp out)
      (write-string (prin1-to-string object) out))
     (t
      (error "ELISP:PRIN1 unsupported stream: ~S" out))))
  object)

(cl:defun princ (object &optional stream)
  "Bring-up subset of ELisp `princ'.

STREAM may be a buffer."
  (let ((out (or stream (current-buffer))))
    (cond
     ((bufferp out)
     (with-current-buffer out
        (typecase object
          (null nil)
          (cl:string (insert object))
          (unibyte-string (insert object))
          (t (insert (prin1-to-string object))))))
     ((streamp out)
      (typecase object
        (null nil)
        (cl:string (write-string object out))
        (unibyte-string (write-string (%elisp-string->cl-string object) out))
        (t (write-string (prin1-to-string object) out))))
     (t
      (error "ELISP:PRINC unsupported stream: ~S" out))))
  object)

(cl:defun point ()
  (elisp-buffer-point *current-buffer*))

(cl:defun point-marker ()
  "Bring-up subset of ELisp `point-marker'."
  (let ((m (make-elisp-marker :buffer *current-buffer*
                              :position (point)
                              :edit-index (%buffer-edit-index *current-buffer*))))
    (%buffer-register-marker *current-buffer* m)
    m))

(cl:defun copy-marker (marker &optional insertion-type)
  "Bring-up subset of ELisp `copy-marker'."
  (etypecase marker
    (elisp-marker
     (let* ((marker (%marker-sync marker))
            (buf (elisp-marker-buffer marker)))
       (let ((m (make-elisp-marker
                 :buffer buf
                 :position (elisp-marker-position marker)
                 :insertion-type (and insertion-type t)
                 :edit-index (if buf (%buffer-edit-index buf) 0))))
         (%buffer-register-marker buf m)
         m)))
    (integer
     (let ((m (make-elisp-marker :buffer *current-buffer*
                                 :position marker
                                 :insertion-type (and insertion-type t)
                                 :edit-index (%buffer-edit-index *current-buffer*))))
       (%buffer-register-marker *current-buffer* m)
       m))))

(cl:defun point-min ()
  1)

(cl:defun point-max ()
  (1+ (length (elisp-buffer-text *current-buffer*))))

(cl:defvar tab-width 8)

(cl:defun current-column ()
  "Bring-up subset of ELisp `current-column'."
  (let* ((txt (elisp-buffer-text *current-buffer*))
         ;; ELisp point is 1-based, and points between characters.
         (idx (1- (point)))
         (line-start (or (cl:position #\Newline txt :end idx :from-end t) -1))
         (col 0))
    (loop for i from (1+ line-start) below idx do
      (let ((ch (char txt i)))
        (if (char= ch #\Tab)
            (incf col (- tab-width (mod col tab-width)))
            (incf col 1))))
    col))

(cl:defun string-width (string &optional _from _to _buffer)
  "Bring-up subset of ELisp `string-width'."
  (declare (cl:ignore _from _to _buffer))
  (unless (stringp string)
    (error "ELISP:STRING-WIDTH expects a string, got: ~S" string))
  (length (%elisp-string->cl-string string)))

(cl:defun window-width (&optional _window _pixelwise)
  "Bring-up subset of ELisp `window-width'."
  (declare (cl:ignore _window _pixelwise))
  (handler-case
      (multiple-value-bind (_rows cols) (clemacs::tty-winsize)
        (declare (cl:ignore _rows))
        (if (and (integerp cols) (> cols 0)) cols 80))
    (cl:error () 80)))

(cl:defun forward-comment (count &optional limit)
  "Bring-up subset of ELisp `forward-comment'.

This is currently just enough for pp.el: skip whitespace and `;` line comments."
  (declare (cl:ignore count))
  (let* ((txt (elisp-buffer-text *current-buffer*))
         (stop (or limit (point-max)))
         (pos (point)))
    (labels ((at (p)
               (and (<= (point-min) p) (< p stop)
                    (char txt (1- p)))))
      (loop while (< pos stop) do
        (let ((ch (at pos)))
          (cond
           ((null ch) (return))
           ((or (char= ch #\Space)
                (char= ch #\Tab)
                (char= ch #\Newline)
                (char= ch #\Return)
                (char= ch #\Page))
            (incf pos))
           ((char= ch #\;)
            (loop while (and (< pos stop)
                             (let ((c (at pos)))
                               (and c (not (char= c #\Newline)))))
                  do (incf pos))
            (when (and (< pos stop) (char= (at pos) #\Newline))
              (incf pos)))
           (t (return))))))
    (goto-char pos)
    nil))

(cl:defun goto-char (pos)
  "Bring-up subset of ELisp `goto-char'.

Emacs clamps positions outside the buffer to the nearest valid position."
  (let* ((p (%pos pos))
         (p* (max (point-min) (min p (point-max)))))
    (setf (elisp-buffer-point *current-buffer*) p*)
    p*))

(cl:defun forward-char (&optional n)
  "Bring-up subset of ELisp `forward-char'."
  (let* ((n (or n 1))
         (target (+ (point) n)))
    (unless (integerp n)
      (error "ELISP:FORWARD-CHAR bad arg: ~S" n))
    (cond
     ((< target (point-min))
      (goto-char (point-min))
      (signal 'beginning-of-buffer nil))
     ((> target (point-max))
      (goto-char (point-max))
      (signal 'end-of-buffer nil))
     (t
      (goto-char target)
      nil))))

(cl:defun forward-line (&optional n)
  "Bring-up subset of ELisp `forward-line'."
  (let* ((n (or n 1))
         (txt (elisp-buffer-text *current-buffer*))
         (moved 0))
    (unless (integerp n)
      (error "ELISP:FORWARD-LINE bad arg: ~S" n))
    (labels ((next-line-start (p)
               (let* ((idx (1- p))
                      (nl (cl:position #\Newline txt :start idx)))
                 (if nl
                     (+ nl 2)
                     (point-max))))
             (prev-line-start (p)
               (let* ((idx (1- p))
                      (nl (cl:position #\Newline txt :end idx :from-end t)))
                 (if nl
                     (let* ((nl2 (cl:position #\Newline txt :end nl :from-end t)))
                       (if nl2 (+ nl2 2) (point-min)))
                     (point-min)))))
      (cond
       ((> n 0)
        (dotimes (_ n)
          (let ((p (point)))
            (when (>= p (point-max))
              (return))
            (goto-char (next-line-start p))
            (incf moved))))
       ((< n 0)
        (dotimes (_ (- n))
          (let ((p (point)))
            (when (<= p (point-min))
              (return))
            (goto-char (prev-line-start p))
            (incf moved))))))
    ;; Emacs returns 0 when it moved N lines, otherwise the number of
    ;; lines remaining.  We approximate with (N - MOVED) for positive N.
    (cond
     ((>= n 0) (- n moved))
     (t (+ n moved)))))

(cl:defun line-end-position (&optional n)
  "Bring-up subset of ELisp `line-end-position'."
  (let ((n (or n 1)))
    (unless (and (integerp n) (> n 0))
      (error "ELISP:LINE-END-POSITION bad arg: ~S" n))
    (save-excursion
      (when (> n 1)
        (forward-line (1- n)))
      (let* ((txt (elisp-buffer-text *current-buffer*))
             (idx (1- (point)))
             (nl (cl:position #\Newline txt :start idx)))
        (if nl
            (1+ nl)
            (point-max))))))

(cl:defun line-beginning-position (&optional n)
  "Bring-up subset of ELisp `line-beginning-position'."
  (let ((n (or n 1)))
    (unless (and (integerp n) (> n 0))
      (error "ELISP:LINE-BEGINNING-POSITION bad arg: ~S" n))
    (save-excursion
      (when (> n 1)
        (forward-line (1- n)))
      (let* ((txt (elisp-buffer-text *current-buffer*))
             (idx (1- (point)))
             (nl (cl:position #\Newline txt :end idx :from-end t)))
        (if nl
            (+ nl 2)
            (point-min))))))

(cl:defun beginning-of-line (&optional n)
  "Bring-up subset of ELisp `beginning-of-line'."
  (let ((n (or n 1)))
    (unless (integerp n)
      (error "ELISP:BEGINNING-OF-LINE bad arg: ~S" n))
    (when (/= n 1)
      (forward-line (1- n)))
    (goto-char (line-beginning-position))
    nil))

(cl:defun end-of-line (&optional n)
  "Bring-up subset of ELisp `end-of-line'."
  (let ((n (or n 1)))
    (unless (integerp n)
      (error "ELISP:END-OF-LINE bad arg: ~S" n))
    (when (/= n 1)
      (forward-line (1- n)))
    (goto-char (line-end-position))
    nil))

(cl:defun backward-char (&optional n)
  "Bring-up subset of ELisp `backward-char'."
  (let ((n (or n 1)))
    (unless (integerp n)
      (error "ELISP:BACKWARD-CHAR bad arg: ~S" n))
    (forward-char (- n))))

(cl:defun back-to-indentation ()
  "Bring-up subset of ELisp `back-to-indentation'."
  (beginning-of-line)
  (skip-chars-forward " \t")
  nil)

(cl:defun current-indentation ()
  "Bring-up subset of ELisp `current-indentation'."
  (save-excursion
    (back-to-indentation)
    (current-column)))

(cl:defun delete-horizontal-space (&optional backward-only)
  "Bring-up subset of ELisp `delete-horizontal-space'."
  (let ((start (point))
        (end (point)))
    (loop while (let ((c (char-before start)))
                  (and c (or (= c (char-code #\Space))
                             (= c (char-code #\Tab)))))
          do (decf start))
    (unless backward-only
      (loop while (let ((c (char-after end)))
                    (and c (or (= c (char-code #\Space))
                               (= c (char-code #\Tab)))))
            do (incf end)))
    (when (< start end)
      (delete-region start end))
    nil))

(cl:defun indent-to (column &optional minimum)
  "Bring-up subset of ELisp `indent-to' (spaces only)."
  (unless (and (integerp column) (>= column 0))
    (error "ELISP:INDENT-TO bad column: ~S" column))
  (when minimum
    (unless (and (integerp minimum) (>= minimum 0))
      (error "ELISP:INDENT-TO bad minimum: ~S" minimum)))
  (let* ((cur (current-column))
         (need (max 0 (- column cur)))
         (need (if minimum (max minimum need) need)))
    (when (> need 0)
      (insert (cl:make-string need :initial-element #\Space)))
    (current-column)))

(cl:defun indent-to-left-margin ()
  "Bring-up subset of ELisp `indent-to-left-margin'."
  (indent-to 0))

(cl:defun use-region-p ()
  "Bring-up stub for ELisp `use-region-p'."
  nil)

(cl:defun region-beginning ()
  "Bring-up stub for ELisp `region-beginning'."
  (error "ELISP:REGION-BEGINNING not implemented"))

(cl:defun region-end ()
  "Bring-up stub for ELisp `region-end'."
  (error "ELISP:REGION-END not implemented"))

(cl:defun point-max-marker ()
  (let ((m (make-elisp-marker :buffer *current-buffer*
                              :position (point-max)
                              :edit-index (%buffer-edit-index *current-buffer*))))
    (%buffer-register-marker *current-buffer* m)
    m))

(cl:defun set-marker (marker position &optional buffer)
  (unless (elisp-marker-p marker)
    (error "ELISP:SET-MARKER expected marker, got: ~S" marker))
  (let ((old (elisp-marker-buffer marker)))
    (cond
     ((null position)
      (when (elisp-buffer-p old)
        (%buffer-unregister-marker old marker)))
     (t
      (let ((new (or buffer *current-buffer*)))
        (when (and (elisp-buffer-p old) (not (eq old new)))
          (%buffer-unregister-marker old marker))))))
  (cond
   ((null position)
    (setf (elisp-marker-buffer marker) nil
          (elisp-marker-position marker) nil
          (elisp-marker-edit-index marker) 0))
   (t
    (unless (and (integerp position) (plusp position))
      (error "ELISP:SET-MARKER bad position: ~S" position))
    (let ((buf (or buffer *current-buffer*)))
      (setf (elisp-marker-buffer marker) buf
            (elisp-marker-position marker) (max (point-min)
                                                (min position (1+ (length (elisp-buffer-text buf)))))
            (elisp-marker-edit-index marker) (%buffer-edit-index buf))
      (%buffer-register-marker buf marker))))
  marker)

(cl:defun %pos (x)
  (etypecase x
    (integer x)
    (elisp-marker (or (marker-position x) (error "Marker has no position")))))

(cl:defun %num (x)
  (typecase x
    (elisp-marker (%pos x))
    (integer x)
    (real x)
    (t (error "ELISP: expected a number/marker, got: ~S" x))))

(cl:defun + (&rest args)
  "Bring-up subset of ELisp `+'."
  (if (null args)
      0
      (reduce #'cl:+ args :key #'%num :initial-value 0)))

(cl:defun - (x &rest more)
  "Bring-up subset of ELisp `-'."
  (if (null more)
      (cl:- (%num x))
      (reduce #'cl:- more :key #'%num :initial-value (%num x))))

(cl:defun 1+ (x)
  "Bring-up subset of ELisp `1+'."
  (+ x 1))

(cl:defun 1- (x)
  "Bring-up subset of ELisp `1-'."
  (- x 1))

(cl:defun < (a b &rest more)
  "Bring-up subset of ELisp `<'."
  (let ((prev (%num a))
        (cur (%num b)))
    (unless (cl:< prev cur)
      (return-from < nil))
    (dolist (x more t)
      (setf prev cur
            cur (%num x))
      (unless (cl:< prev cur)
        (return-from < nil)))))

(cl:defun <= (a b &rest more)
  "Bring-up subset of ELisp `<='."
  (let ((prev (%num a))
        (cur (%num b)))
    (unless (cl:<= prev cur)
      (return-from <= nil))
    (dolist (x more t)
      (setf prev cur
            cur (%num x))
      (unless (cl:<= prev cur)
        (return-from <= nil)))))

(cl:defun > (a b &rest more)
  "Bring-up subset of ELisp `>'."
  (let ((prev (%num a))
        (cur (%num b)))
    (unless (cl:> prev cur)
      (return-from > nil))
    (dolist (x more t)
      (setf prev cur
            cur (%num x))
      (unless (cl:> prev cur)
        (return-from > nil)))))

(cl:defun >= (a b &rest more)
  "Bring-up subset of ELisp `>='."
  (let ((prev (%num a))
        (cur (%num b)))
    (unless (cl:>= prev cur)
      (return-from >= nil))
    (dolist (x more t)
      (setf prev cur
            cur (%num x))
      (unless (cl:>= prev cur)
        (return-from >= nil)))))

(cl:defun = (a b &rest more)
  "Bring-up subset of ELisp `='."
  (let ((prev (%num a))
        (cur (%num b)))
    (unless (cl:= prev cur)
      (return-from = nil))
    (dolist (x more t)
      (setf prev cur
            cur (%num x))
      (unless (cl:= prev cur)
        (return-from = nil)))))

(cl:defun buffer-substring (start end)
  (let* ((s (%pos start))
         (e (%pos end))
         (txt (elisp-buffer-text *current-buffer*)))
    (when (> s e)
      (error "ELISP:BUFFER-SUBSTRING start > end: ~S ~S" start end))
    (subseq txt (1- s) (1- e))))

(cl:defun buffer-substring-no-properties (start end)
  "Bring-up subset of ELisp `buffer-substring-no-properties'."
  (buffer-substring start end))

(cl:defun delete-region (start end)
  (let* ((s (%pos start))
         (e (%pos end))
         (txt (elisp-buffer-text *current-buffer*)))
    (when (> s e)
      (error "ELISP:DELETE-REGION start > end: ~S ~S" start end))
    (%buffer-record-delete *current-buffer* s e)
    (setf (elisp-buffer-text *current-buffer*)
          (concatenate 'cl:string (subseq txt 0 (1- s)) (subseq txt (1- e))))
    (when (> (point) (point-max))
      (goto-char (point-max)))
    nil))

(cl:defun delete-char (n &optional _killflag)
  "Bring-up subset of ELisp `delete-char'."
  (declare (cl:ignore _killflag))
  (unless (integerp n)
    (error "ELISP:DELETE-CHAR expects integer N, got: ~S" n))
  (cond
   ((zerop n) nil)
   ((plusp n)
    (delete-region (point) (min (point-max) (+ (point) n))))
   (t
    (delete-region (max (point-min) (+ (point) n)) (point))))
  nil)

(cl:defun %set-buffer-match-data (mstart mend reg-starts reg-ends &key (base 0))
  (let ((md nil))
    (push (and (integerp mstart) (<= 0 mstart) (+ base mstart 1)) md)
    (push (and (integerp mend) (<= 0 mend) (+ base mend 1)) md)
    (when reg-starts
      (loop for rs across reg-starts
            for re across reg-ends do
              (push (and (integerp rs) (<= 0 rs) (+ base rs 1)) md)
              (push (and (integerp re) (<= 0 re) (+ base re 1)) md)))
    (setf *match-data* (nreverse md)
          *match-source-string* nil)
    md))

(cl:defun looking-at (regexp)
  "Bring-up subset of ELisp `looking-at'."
  (unless (stringp regexp)
    (error "ELISP:LOOKING-AT expects a string, got: ~S" regexp))
  (let* ((s (elisp-buffer-text *current-buffer*))
         (start (1- (point))))
    ;; Important: `looking-at' must only try a match at point (no forward search),
    ;; otherwise it can become pathologically slow on large buffers (pp.el relies
    ;; on this being cheap).  Avoid SUBSEQ here; use an anchored scanner and set
    ;; :REAL-START-POS to the match start so \\A behaves like "at point".
    (multiple-value-bind (mstart mend reg-starts reg-ends)
        (cl-ppcre:scan (%string-match-anchored-scanner regexp case-fold-search)
                       s
                       :start start
                       :end (length s)
                       :real-start-pos start)
      (if (or (null mstart) (/= mstart start))
          (progn
            (setf *match-data* nil *match-source-string* nil)
            nil)
          (progn
            (%set-buffer-match-data mstart mend reg-starts reg-ends)
            t)))))

(cl:defun looking-back (regexp &optional limit _greedy)
  "Bring-up subset of ELisp `looking-back'."
  (declare (cl:ignore _greedy))
  (unless (stringp regexp)
    (error "ELISP:LOOKING-BACK expects a string, got: ~S" regexp))
  (let* ((s (elisp-buffer-text *current-buffer*))
         (end (1- (point)))
         (lim (max (point-min) (or limit (point-min))))
         (lim-idx (1- lim)))
    (when (< end lim-idx)
      (setf *match-data* nil *match-source-string* nil)
      (return-from looking-back nil))
    (let* ((sub (subseq s lim-idx end))
           (scanner (%string-match-scanner regexp case-fold-search))
           (best nil)
           (best-reg-starts nil)
           (best-reg-ends nil))
      (cl-ppcre:do-scans (ms me rs re scanner sub)
        (when (= me (length sub))
          (setf best ms best-reg-starts rs best-reg-ends re)))
      (if (null best)
          (progn
            (setf *match-data* nil *match-source-string* nil)
            nil)
          (progn
            (%set-buffer-match-data best (length sub) best-reg-starts best-reg-ends :base lim-idx)
            t)))))

(cl:defun re-search-forward (regexp &optional bound noerror count)
  "Bring-up subset of ELisp `re-search-forward'."
  (unless (stringp regexp)
    (error "ELISP:RE-SEARCH-FORWARD expects a string, got: ~S" regexp))
  (let ((count (or count 1)))
    (unless (and (integerp count) (< 0 count))
      (error "ELISP:RE-SEARCH-FORWARD bad count: ~S" count))
    (loop repeat count
          for s = (elisp-buffer-text *current-buffer*)
          for start = (1- (point))
          for end = (if bound (max 0 (1- (%pos bound))) (length s))
          do
            (multiple-value-bind (mstart mend reg-starts reg-ends)
                (cl-ppcre:scan (%string-match-scanner regexp case-fold-search)
                               s
                               :start start
                               :end end
                               :real-start-pos 0)
              (when (null mstart)
                (setf *match-data* nil *match-source-string* nil)
                (when noerror
                  (return-from re-search-forward nil))
                (error "Search failed: %S" regexp))
              (%set-buffer-match-data mstart mend reg-starts reg-ends)
              (goto-char (1+ mend))))
    (point)))

(cl:defun re-search-backward (regexp &optional bound noerror count)
  "Bring-up subset of ELisp `re-search-backward'."
  (unless (stringp regexp)
    (error "ELISP:RE-SEARCH-BACKWARD expects a string, got: ~S" regexp))
  ;; Fast-path for pp.el's `pp--within-fill-column-p': it calls
  ;;   (re-search-backward "^\\|\n" ...)
  ;; which is just "beginning of line or newline".  Implement this without
  ;; regex to avoid pathological behavior and to more closely match Emacs.
  (let ((re (%elisp-string->cl-string regexp)))
    (when (and (= (length re) 4)
               (char= (char re 0) #\^)
               (char= (char re 1) #\\)
               (char= (char re 2) #\|)
               (char= (char re 3) #\Newline))
      (let* ((count (or count 1)))
        (unless (and (integerp count) (< 0 count))
          (error "ELISP:RE-SEARCH-BACKWARD bad count: ~S" count))
        ;; Only COUNT=1 is used by pp.el; implement just that for now.
        (unless (= count 1)
          (error "ELISP:RE-SEARCH-BACKWARD unsupported COUNT for ^\\\\|\\n fast-path: ~S" count))
        (let* ((txt (elisp-buffer-text *current-buffer*))
               (end (1- (point)))
               (lim (if bound (max (point-min) (%pos bound)) (point-min)))
               (lim-idx (1- lim))
               (nl (cl:position #\Newline txt :end end :from-end t))
               (bol (if nl (+ nl 2) (point-min))))
          (return-from re-search-backward
            (if (< bol lim)
                (progn
                  (setf *match-data* nil *match-source-string* nil)
                  (if noerror nil (error "Search failed: %S" regexp)))
                (progn
                  (setf *match-data* (list bol bol)
                        *match-source-string* nil)
                  (goto-char bol)
                  (point))))))))
  (let ((count (or count 1)))
    (unless (and (integerp count) (< 0 count))
      (error "ELISP:RE-SEARCH-BACKWARD bad count: ~S" count))
    (loop repeat count
          do
            (let* ((s (elisp-buffer-text *current-buffer*))
                   (end (1- (point)))
                   (lim (if bound (max (point-min) (%pos bound)) (point-min)))
                   (lim-idx (1- lim)))
              (when (< end lim-idx)
                (setf *match-data* nil *match-source-string* nil)
                (when noerror
                  (return-from re-search-backward nil))
                (error "Search failed: %S" regexp))
              ;; Avoid `cl-ppcre:do-scans' here: patterns like "^\\|\n" can
              ;; include empty matches (via "^"), and some scan loops can get
              ;; stuck if the match has zero length.  Instead, scan forward
              ;; manually and force progress on empty matches.
              ;;
              ;; Also: do *not* slice SUBSEQ here.  Anchors like `^` should be
              ;; interpreted relative to the whole buffer (Emacs `^` means
              ;; beginning-of-line, which we're approximating with `(?<=\\n)`),
              ;; so we scan the full buffer string with :START/:END bounds.
              (let* ((scanner (%string-match-scanner regexp case-fold-search))
                     (pos lim-idx)
                     (best-ms nil)
                     (best-me nil)
                     (best-rs nil)
                     (best-re nil)
                     (max-end end))
                (loop while (<= pos max-end) do
                  (multiple-value-bind (ms me rs re)
                      (cl-ppcre:scan scanner s :start pos :end max-end :real-start-pos 0)
                    (when (null ms)
                      (return))
                    (setf best-ms ms
                          best-me me
                          best-rs rs
                          best-re re)
                    (setf pos (if (= ms me) (1+ me) me))))
                (when (null best-ms)
                  (setf *match-data* nil *match-source-string* nil)
                  (when noerror
                    (return-from re-search-backward nil))
                  (error "Search failed: %S" regexp))
                (let ((pos (1+ best-ms)))
                  (%set-buffer-match-data best-ms best-me best-rs best-re)
                  (goto-char pos))))))
    (point))

(cl:defun replace-match (replacement &optional _fixedcase _literal _string _subexp)
  "Bring-up subset of ELisp `replace-match' (buffer-only, literal replacement)."
  (declare (cl:ignore _fixedcase _literal _string _subexp))
  (unless (stringp replacement)
    (error "ELISP:REPLACE-MATCH expects a string, got: ~S" replacement))
  (let ((start (match-beginning 0))
        (end (match-end 0)))
    (unless (and start end)
      (error "ELISP:REPLACE-MATCH no match data"))
    (delete-region start end)
    (goto-char start)
    (insert replacement)
    nil))

(cl:defun insert (&rest parts)
  (let* ((s (with-output-to-string (out)
              (dolist (p parts)
                (typecase p
                  (null nil)
                  (cl:string (write-string p out))
                  (unibyte-string (write-string (%elisp-string->cl-string p) out))
                  (character (write-char p out))
                  (t (write-string (princ-to-string p) out))))))
         (txt (elisp-buffer-text *current-buffer*))
         (at (point))
         (idx (1- at)))
    (when (and (uiop:getenv "CLEMACS_PP_DEBUG")
               (> (length s) 0)
               (char= (char s 0) #\Newline))
      (labels ((safe-char (i)
                 (and (<= 0 i) (< i (length txt)) (char txt i)))
               (sym-ch-p (ch)
                 (and ch
                      (or (and (char>= ch #\a) (char<= ch #\z))
                          (and (char>= ch #\A) (char<= ch #\Z))
                          (and (char>= ch #\0) (char<= ch #\9))
                          (char= ch #\:)
                          (char= ch #\-)
                          (char= ch #\_))))
               (snippet (center &key (radius 24))
                 (let* ((s (max 0 (- center radius)))
                        (e (min (length txt) (+ center radius))))
                   (subseq txt s e))))
        (let* ((prev (safe-char (1- idx)))
               (next (safe-char idx)))
          ;; Detect newlines inserted *inside* tokens (pp.el should never do
          ;; this for symbols/keywords; it indicates a scanning/indent bug).
          (when (and (sym-ch-p prev) (sym-ch-p next))
            (let ((path "build/clemacs/tmp/pp-debug.out"))
              (ensure-directories-exist path)
              (with-open-file (out path
                                   :direction :output
                                   :if-exists :append
                                   :if-does-not-exist :create)
                (cl:format out "~&[pp-debug] newline split at pos=~D col=~D buf=~S~%"
                           at (current-column) (elisp-buffer-name *current-buffer*))
                (cl:format out "  before: ~S~%" (snippet (max 0 (- idx 1))))
                (cl:format out "  after:  ~S~%" (snippet idx))
                #+sbcl
                (sb-debug:print-backtrace :stream out :count 50)
                (finish-output out)))))))
    (%buffer-record-insert *current-buffer* at (length s))
    (setf (elisp-buffer-text *current-buffer*)
          (concatenate 'cl:string (subseq txt 0 idx) s (subseq txt idx)))
    (goto-char (+ (point) (length s)))
    nil))

(cl:defun insert-and-inherit (&rest parts)
  "Bring-up subset of ELisp `insert-and-inherit'."
  (apply #'insert parts))

(cl:defun insert-before-markers-and-inherit (&rest parts)
  "Bring-up subset of ELisp `insert-before-markers-and-inherit'."
  (apply #'insert parts))

(cl:defun newline (&optional n)
  "Bring-up subset of ELisp `newline'."
  (let ((n (or n 1)))
    (unless (and (integerp n) (>= n 0))
      (error "ELISP:NEWLINE bad arg: ~S" n))
    (dotimes (_ n)
      (insert #\Newline))
    nil))

(cl:defun buffer-string ()
  "Bring-up subset of ELisp `buffer-string'."
  (elisp-buffer-text *current-buffer*))

(cl:defun bobp ()
  "Bring-up subset of ELisp `bobp'."
  (= (point) (point-min)))

(cl:defun eobp ()
  "Bring-up subset of ELisp `eobp'."
  (= (point) (point-max)))

(cl:defun char-after (&optional pos)
  "Bring-up subset of ELisp `char-after'."
  (let* ((p (if pos (%pos pos) (point))))
    (when (and (integerp p) (<= (point-min) p) (< p (point-max)))
      (char-code (char (elisp-buffer-text *current-buffer*) (1- p))))))

(cl:defun char-before (&optional pos)
  "Bring-up subset of ELisp `char-before'."
  (let* ((p (if pos (%pos pos) (point))))
    (when (and (integerp p) (< (point-min) p) (<= p (point-max)))
      (char-code (char (elisp-buffer-text *current-buffer*) (- p 2))))))

(cl:defun bolp ()
  "Bring-up subset of ELisp `bolp'."
  (or (bobp)
      (let ((c (char-before)))
        (and c (= c (char-code #\Newline))))))

(cl:defun eolp ()
  "Bring-up subset of ELisp `eolp'."
  (or (eobp)
      (let ((c (char-after)))
        (and c (= c (char-code #\Newline))))))

(cl:defun %char-in-skip-set-p (ch set invertp)
  (let ((in (find ch set :test #'char=)))
    (if invertp (not in) (and in t))))

(cl:defun skip-chars-forward (chars &optional limit)
  "Bring-up subset of ELisp `skip-chars-forward'."
  (unless (stringp chars)
    (error "ELISP:SKIP-CHARS-FORWARD expects a string, got: ~S" chars))
  (let* ((set (%elisp-string->cl-string chars))
         (invertp (and (> (length set) 0) (char= (char set 0) #\^)))
         (set (if invertp (subseq set 1) set))
         (stop (or limit (point-max)))
         (pos (point))
         (moved 0))
    (loop while (and (< pos stop)
                     (let ((c (char-after pos)))
                       (and c (%char-in-skip-set-p (code-char c) set invertp))))
          do (incf pos) (incf moved))
    (goto-char pos)
    moved))

(cl:defun skip-chars-backward (chars &optional limit)
  "Bring-up subset of ELisp `skip-chars-backward'."
  (unless (stringp chars)
    (error "ELISP:SKIP-CHARS-BACKWARD expects a string, got: ~S" chars))
  (let* ((set (%elisp-string->cl-string chars))
         (invertp (and (> (length set) 0) (char= (char set 0) #\^)))
         (set (if invertp (subseq set 1) set))
         (stop (or limit (point-min)))
         (pos (point))
         (moved 0))
    (loop while (and (> pos stop)
                     (let ((c (char-before pos)))
                       (and c (%char-in-skip-set-p (code-char c) set invertp))))
          do (decf pos) (incf moved))
    (goto-char pos)
    moved))

(cl:defun %syntax-w_-p (ch)
  ;; Pragmatic approximation for Emacs `\\sw' and `\\s_' classes in
  ;; `emacs-lisp-mode-syntax-table': include alnum plus common symbol chars.
  (or (alphanumericp ch)
      (find ch "_-:" :test #'char=)))

(cl:defun skip-syntax-forward (syntax &optional limit)
  "Bring-up subset of ELisp `skip-syntax-forward'.

Only supports the `w' and `_` classes (and negation with `^`), which is enough
for upstream ERT's `ert--make-xrefs-region'."
  (unless (stringp syntax)
    (error "ELISP:SKIP-SYNTAX-FORWARD expects a string, got: ~S" syntax))
  (let* ((spec (%elisp-string->cl-string syntax))
         (invertp (and (> (length spec) 0) (char= (char spec 0) #\^)))
         (classes (if invertp (subseq spec 1) spec))
         (stop (or limit (point-max)))
         (pos (point))
         (moved 0))
    (labels ((in-classes-p (ch)
               (let ((ok nil))
                 (loop for c across classes do
                   (when (or (and (char= c #\w) (%syntax-w_-p ch))
                             (and (char= c #\_) (%syntax-w_-p ch)))
                     (setf ok t) (return)))
                 (if invertp (not ok) ok))))
      (loop while (and (< pos stop)
                       (let ((c (char-after pos)))
                         (and c (in-classes-p (code-char c)))))
            do (incf pos) (incf moved)))
    (goto-char pos)
    moved))

(cl:defun skip-syntax-backward (syntax &optional limit)
  "Bring-up subset of ELisp `skip-syntax-backward'."
  (unless (stringp syntax)
    (error "ELISP:SKIP-SYNTAX-BACKWARD expects a string, got: ~S" syntax))
  (let* ((spec (%elisp-string->cl-string syntax))
         (invertp (and (> (length spec) 0) (char= (char spec 0) #\^)))
         (classes (if invertp (subseq spec 1) spec))
         (stop (or limit (point-min)))
         (pos (point))
         (moved 0))
    (labels ((in-classes-p (ch)
               (let ((ok nil))
                 (loop for c across classes do
                   (when (or (and (char= c #\w) (%syntax-w_-p ch))
                             (and (char= c #\_) (%syntax-w_-p ch)))
                     (setf ok t) (return)))
                 (if invertp (not ok) ok))))
      (loop while (and (> pos stop)
                       (let ((c (char-before pos)))
                         (and c (in-classes-p (code-char c)))))
            do (decf pos) (incf moved)))
    (goto-char pos)
    moved))

(cl:defun search-backward (needle &optional bound noerror _count)
  "Bring-up subset of ELisp `search-backward'."
  (declare (cl:ignore _count))
  (unless (stringp needle)
    (error "ELISP:SEARCH-BACKWARD expects a string, got: ~S" needle))
  (let* ((n (%elisp-string->cl-string needle))
         (txt (elisp-buffer-text *current-buffer*))
         (end (1- (point)))
         (bnd (max (point-min) (if bound (%pos bound) (point-min))))
         (bnd-idx (1- bnd)))
    (let ((idx (search n txt :start2 bnd-idx :end2 end :from-end t :test #'char=)))
      (cond
       ((null idx)
        (if noerror nil (error "ELISP:SEARCH-BACKWARD not found: ~S" needle)))
       (t
        (goto-char (1+ idx))
        (point))))))

(cl:defun scan-sexps (from count)
  "Bring-up subset of ELisp `scan-sexps'."
  (unless (integerp count)
    (error "ELISP:SCAN-SEXPS expects integer COUNT, got: ~S" count))
  (let ((from (%pos from)))
    (unless (integerp from)
      (error "ELISP:SCAN-SEXPS expects integer/marker FROM, got: ~S" from))
  (when (zerop count)
    (return-from scan-sexps from))
  (when (minusp count)
    (error "ELISP:SCAN-SEXPS negative COUNT not supported: ~S" count))
	  (let ((txt (elisp-buffer-text *current-buffer*))
	        (pos from))
	    (labels ((whitespacep (ch)
	               (or (char= ch #\Space)
	                   (char= ch #\Tab)
	                   (char= ch #\Return)
	                   (char= ch #\Newline)))
	             (atom-delim-p (ch)
	               (or (whitespacep ch)
	                   (find ch "()[]{}\"" :test #'char=)))
	             (peek (p)
	               (when (and (<= (point-min) p) (< p (point-max)))
	                 (char txt (1- p))))
	             (skip-ws ()
	               (loop for ch = (peek pos)
	                     while (and ch (whitespacep ch)) do
	                       (incf pos)))
             (scan-string ()
               ;; starting at opening quote
               (incf pos) ; skip initial "
               (loop for ch = (peek pos) while ch do
                 (cond
                  ((char= ch #\\) (incf pos 2))
                  ((char= ch #\") (incf pos) (return))
                  (t (incf pos)))))
             (scan-delims (open close)
               (declare (cl:ignore open))
               (let ((stack (list close)))
                 (incf pos) ; skip OPEN
                 (loop while stack do
                   (let ((ch (peek pos)))
                     (when (null ch) (return-from scan-sexps nil))
                     (cond
                      ((char= ch #\") (scan-string))
                      ((char= ch #\() (push #\) stack) (incf pos))
                      ((char= ch #\[) (push #\] stack) (incf pos))
                      ((char= ch #\{) (push #\} stack) (incf pos))
                      ((find ch ")]}" :test #'char=)
                       (unless (char= ch (car stack))
                         (return-from scan-sexps nil))
                       (pop stack)
                       (incf pos))
                      (t (incf pos)))))))
	             (scan-atom ()
	               (loop for ch = (peek pos)
	                     while (and ch (not (atom-delim-p ch))) do
	                       (incf pos)))
	             (scan-one ()
	               (skip-ws)
	               (let ((ch (peek pos)))
	                 (when (null ch) (return-from scan-sexps nil))
	                 (cond
	                  ((find ch "'`,#" :test #'char=) (incf pos) (scan-one))
	                  ((char= ch #\") (scan-string))
	                  ((char= ch #\() (scan-delims #\( #\)))
	                  ((char= ch #\[) (scan-delims #\[ #\]))
	                  ((char= ch #\{) (scan-delims #\{ #\}))
	                  ;; Treat closing delimiters as a 1-char sexp so callers like
	                  ;; pp.el's pp-fill don't get stuck when scanning at ")...".
	                  ((find ch ")]}" :test #'char=) (incf pos))
	                  (t (scan-atom))))))
      (dotimes (i count)
        (declare (ignorable i))
        (scan-one))
      (when (and (uiop:getenv "CLEMACS_PP_TRACE_SCAN_SEXPS")
                 (= count 1))
        (labels ((peek* (p)
                   (when (and (<= (point-min) p) (< p (point-max)))
                     (char txt (1- p)))))
          (let ((c0 (peek* from))
                (c1 (peek* (1+ from))))
            (when (and c0 c1 (char= c0 #\:) (alphanumericp c1))
              (let ((path "build/clemacs/tmp/scan-sexps-debug.out"))
                (ensure-directories-exist path)
                (with-open-file (out path
                                     :direction :output
                                     :if-exists :append
                                     :if-does-not-exist :create)
                  (cl:format out "~&scan-sexps from=~D => ~D ; token=~S~%"
                             from pos
                             (subseq txt (1- from) (max 0 (min (length txt) (1- pos)))))
                  #+sbcl
                  (sb-debug:print-backtrace :stream out :count 20)
                  (finish-output out))))))))
      pos)))
(cl:defun %column-at-pos (pos)
  (let ((saved (point)))
    (unwind-protect
        (progn (goto-char pos) (current-column))
      (goto-char saved))))

(cl:defun indent-according-to-mode ()
  "Bring-up subset of ELisp `indent-according-to-mode'."
  (when indent-line-function
    (funcall indent-line-function))
  nil)

(cl:defun indent-rigidly (start end columns)
  "Bring-up subset of ELisp `indent-rigidly'."
  (let* ((s (%pos start))
         (e (%pos end))
         (cols columns))
    (unless (and (integerp cols) (<= 0 cols))
      (error "ELISP:INDENT-RIGIDLY bad columns: ~S" columns))
    (when (> s e)
      (error "ELISP:INDENT-RIGIDLY start > end: ~S ~S" start end))
    (when (zerop cols)
      (return-from indent-rigidly nil))
    ;; Emacs indents lines whose beginning falls within START..END.
    ;; In particular, if START is in the middle of a line, that line is not
    ;; indented (which is important for pp.el's use of indent-rigidly).
    (let* ((txt (elisp-buffer-text *current-buffer*))
           (pad (cl:make-string cols :initial-element #\Space))
           (insert-pos nil)
           (p0 (point)))
      ;; If START is exactly at BOL, include it.
      (when (or (= s (point-min))
                (let ((c (char-before s)))
                  (and c (= c (char-code #\Newline)))))
        (push s insert-pos))
      ;; Include each line start after a newline within the region.
      (let ((idx (1- s))
            (end-idx (max 0 (1- e))))
        (loop for nl = (cl:position #\Newline txt :start idx :end end-idx)
              while nl do
                (let ((ls (+ nl 2)))
                  (when (and (<= s ls) (< ls e))
                    (push ls insert-pos)))
                (setf idx (1+ nl))))
      (when insert-pos
        ;; Apply inserts from the end so earlier recorded positions remain
        ;; stable. This keeps markers consistent as well.
        (dolist (pos (sort insert-pos #'>))
          (goto-char pos)
          (insert pad))
        (let ((n (count-if (lambda (pos) (<= pos p0)) insert-pos)))
          (goto-char (+ p0 (* cols n))))))
    nil))

(cl:defun erase-buffer ()
  "Bring-up subset of ELisp `erase-buffer'."
  (delete-region (point-min) (point-max))
  (goto-char (point-min))
  nil)

(cl:defun buffer-disable-undo (&optional _buffer)
  "Bring-up stub for ELisp `buffer-disable-undo'."
  (declare (cl:ignore _buffer))
  nil)

(cl:defun buffer-name (&optional buffer)
  "Bring-up subset of ELisp `buffer-name'."
  (let ((buf (or buffer *current-buffer*)))
    (etypecase buf
      (elisp-buffer (elisp-buffer-name buf))
      (null nil))))

(cl:defvar global-mark-ring nil)

(defstruct elisp-window-configuration
  (current-buffer nil))

(cl:defun current-window-configuration ()
  "Bring-up stub for ELisp `current-window-configuration'."
  (make-elisp-window-configuration :current-buffer *current-buffer*))

(cl:defun set-window-configuration (config)
  "Bring-up stub for ELisp `set-window-configuration'."
  (unless (elisp-window-configuration-p config)
    (error "ELISP:SET-WINDOW-CONFIGURATION expected window configuration, got: ~S" config))
  (let ((buf (elisp-window-configuration-current-buffer config)))
    (when buf
      (set-buffer buf)))
  t)

(cl:defun pop-to-buffer (buffer-or-name &optional _action _norecord)
  "Bring-up stub for ELisp `pop-to-buffer'."
  (declare (cl:ignore _action _norecord))
  (let ((buf (or (get-buffer buffer-or-name)
                 (and (stringp buffer-or-name) (get-buffer-create buffer-or-name))
                 (error "ELISP:POP-TO-BUFFER invalid buffer: ~S" buffer-or-name))))
    (set-buffer buf)
    buf))

(cl:defun force-mode-line-update (&optional _all)
  "Bring-up stub for ELisp `force-mode-line-update'."
  (declare (cl:ignore _all))
  nil)

(cl:defun redisplay (&optional _force)
  "Bring-up stub for ELisp `redisplay'."
  (declare (cl:ignore _force))
  nil)

(cl:defun float-time (&optional time)
  "Bring-up subset of ELisp `float-time'."
  (cond
   ((null time) (cl:coerce (get-universal-time) 'double-float))
   ((numberp time) (cl:coerce time 'double-float))
   ((and (consp time) (integerp (car time)) (consp (cdr time)) (integerp (cadr time)))
    ;; Emacs time values are typically (HI LO USEC PSEC) where seconds are
    ;; HI*2^16 + LO and the tail are fractional seconds.
    (let* ((hi (cl:coerce (car time) 'double-float))
           (lo (cl:coerce (cadr time) 'double-float))
           (usec (cl:coerce (or (caddr time) 0) 'double-float))
           (psec (cl:coerce (or (cadddr time) 0) 'double-float)))
      (+ (* hi 65536.0d0) lo (/ usec 1000000.0d0) (/ psec 1000000000000.0d0))))
   (t (error "ELISP:FLOAT-TIME unsupported time: ~S" time))))

(cl:defun time-add (time-a time-b)
  "Bring-up subset of ELisp `time-add'."
  (+ (float-time time-a) (float-time time-b)))

(cl:defun time-subtract (time-a time-b)
  "Bring-up subset of ELisp `time-subtract'."
  (- (float-time time-a) (float-time time-b)))

(cl:defun time-less-p (time-a time-b)
  "Bring-up subset of ELisp `time-less-p'."
  (< (float-time time-a) (float-time time-b)))

;; ---------------------------------------------------------------------------
;; Minimal ewoc surface (enough for upstream ERT results printing bring-up)
;; ---------------------------------------------------------------------------

(defstruct elisp-ewoc-node
  (data nil)
  (location 1 :type integer))

(defstruct elisp-ewoc
  (buffer nil)
  (pretty-printer nil)
  (header "" :type (or cl:string unibyte-string))
  (footer "" :type (or cl:string unibyte-string))
  (nosep nil)
  (nodes nil))

(cl:defun ewoc-create (pretty-printer &optional header footer nosep)
  "Bring-up subset of ELisp `ewoc-create'.

This is a minimal stub used to get upstream ERT's results buffer printing
working. It stores nodes out-of-band and (re)renders on `ewoc-refresh' and
`ewoc-set-hf'."
  (make-elisp-ewoc :buffer (current-buffer)
                   :pretty-printer pretty-printer
                   :header (or header "")
                   :footer (or footer "")
                   :nosep (and nosep t)
                   :nodes nil))

(cl:defun ewoc-set-hf (ewoc header footer)
  "Bring-up subset of ELisp `ewoc-set-hf'."
  (unless (elisp-ewoc-p ewoc)
    (error "ELISP:EWOC-SET-HF expected ewoc, got: ~S" ewoc))
  (setf (elisp-ewoc-header ewoc) (or header "")
        (elisp-ewoc-footer ewoc) (or footer ""))
  (ewoc-refresh ewoc)
  nil)

(cl:defun ewoc-enter-last (ewoc data)
  "Bring-up subset of ELisp `ewoc-enter-last'."
  (unless (elisp-ewoc-p ewoc)
    (error "ELISP:EWOC-ENTER-LAST expected ewoc, got: ~S" ewoc))
  (let ((node (make-elisp-ewoc-node :data data)))
    (setf (elisp-ewoc-nodes ewoc)
          (nconc (elisp-ewoc-nodes ewoc) (list node)))
    node))

(cl:defun ewoc-data (node)
  "Bring-up subset of ELisp `ewoc-data'."
  (unless (elisp-ewoc-node-p node)
    (error "ELISP:EWOC-DATA expected ewoc node, got: ~S" node))
  (elisp-ewoc-node-data node))

(cl:defun ewoc-nth (ewoc n)
  "Bring-up subset of ELisp `ewoc-nth'."
  (unless (elisp-ewoc-p ewoc)
    (error "ELISP:EWOC-NTH expected ewoc, got: ~S" ewoc))
  (let* ((nodes (elisp-ewoc-nodes ewoc))
         (len (length nodes)))
    (cond
     ((null nodes) nil)
     ((minusp n) (nth (+ len n) nodes))
     (t (nth n nodes)))))

(cl:defun ewoc-next (ewoc node)
  "Bring-up subset of ELisp `ewoc-next'."
  (unless (and (elisp-ewoc-p ewoc) (elisp-ewoc-node-p node))
    (error "ELISP:EWOC-NEXT bad args: ~S ~S" ewoc node))
  (loop with seen = nil
        for n in (elisp-ewoc-nodes ewoc) do
          (cond
           (seen (return n))
           ((eq n node) (setf seen t)))
        finally
          (return nil)))

(cl:defun ewoc-prev (ewoc node)
  "Bring-up subset of ELisp `ewoc-prev'."
  (unless (and (elisp-ewoc-p ewoc) (elisp-ewoc-node-p node))
    (error "ELISP:EWOC-PREV bad args: ~S ~S" ewoc node))
  (loop with prev = nil
        for n in (elisp-ewoc-nodes ewoc) do
          (when (eq n node)
            (return prev))
          (setf prev n)
        finally
          (return nil)))

(cl:defun ewoc-location (node)
  "Bring-up subset of ELisp `ewoc-location'."
  (unless (elisp-ewoc-node-p node)
    (error "ELISP:EWOC-LOCATION expected ewoc node, got: ~S" node))
  (elisp-ewoc-node-location node))

(cl:defun ewoc-goto-node (ewoc node)
  "Bring-up subset of ELisp `ewoc-goto-node'."
  (unless (and (elisp-ewoc-p ewoc) (elisp-ewoc-node-p node))
    (error "ELISP:EWOC-GOTO-NODE bad args: ~S ~S" ewoc node))
  (with-current-buffer (elisp-ewoc-buffer ewoc)
    (goto-char (ewoc-location node)))
  nil)

(cl:defun ewoc-locate (ewoc &optional pos _guess)
  "Bring-up subset of ELisp `ewoc-locate'."
  (declare (cl:ignore _guess))
  (unless (elisp-ewoc-p ewoc)
    (error "ELISP:EWOC-LOCATE expected ewoc, got: ~S" ewoc))
  (with-current-buffer (elisp-ewoc-buffer ewoc)
    (let ((p (or pos (point)))
          (best nil))
      (dolist (node (elisp-ewoc-nodes ewoc))
        (when (<= (ewoc-location node) p)
          (setf best node)))
      (or best (car (elisp-ewoc-nodes ewoc))))))

(cl:defun ewoc-invalidate (ewoc _node &rest _ignore)
  "Bring-up subset of ELisp `ewoc-invalidate'."
  (declare (cl:ignore _node _ignore))
  (ewoc-refresh ewoc)
  nil)

(cl:defun ewoc-refresh (ewoc)
  "Bring-up subset of ELisp `ewoc-refresh'."
  (unless (elisp-ewoc-p ewoc)
    (error "ELISP:EWOC-REFRESH expected ewoc, got: ~S" ewoc))
  (with-current-buffer (elisp-ewoc-buffer ewoc)
    (erase-buffer)
    (goto-char (point-min))
    (let ((pp (elisp-ewoc-pretty-printer ewoc)))
      (insert (elisp-ewoc-header ewoc))
      (dolist (node (elisp-ewoc-nodes ewoc))
        (setf (elisp-ewoc-node-location node) (point))
        (funcall pp (ewoc-data node))
        (unless (elisp-ewoc-nosep ewoc)
          (insert #\Newline)))
      (insert (elisp-ewoc-footer ewoc))))
  nil)

(cl:defun natnump (x)
  (and (integerp x) (not (minusp x)) t))

(cl:defun message (format-string &rest args)
  (let ((s (apply #'format format-string args)))
    (with-current-buffer (messages-buffer)
      (goto-char (point-max))
      (insert s #\Newline))
    s))

(cl:defun error-message-string (condition)
  (princ-to-string condition))

(cl:defun backtrace-get-frames (&optional base &rest _keys)
  "Bring-up subset of `backtrace-get-frames'.

Return a list of \"frames\" in the shape (FUN . ARGS), intended for upstream
ERT reporting.  This is not Emacs's native backtrace representation.

On SBCL, we capture a snapshot of the host call stack and convert each host
frame's call into an ELisp-friendly (FUN . ARGS) cons.  On other lisps, fall
back to a tiny stub list."
  (declare (cl:ignore base _keys))
  ;; ERT stores (cdr (backtrace-get-frames ...)) to drop frames above itself,
  ;; so include a sentinel head frame here.
  #+sbcl
  (let ((frames nil))
    (sb-debug:map-backtrace
     (lambda (frame)
       (handler-case
           (multiple-value-bind (call _ok)
               (sb-debug::frame-call-as-list frame 50)
             (declare (cl:ignore _ok))
             (when (consp call)
               (push (cons (car call) (cdr call)) frames)))
         (cl:error () nil)))
     :from :interrupted-frame
     :count 80)
    (let* ((frames (nreverse frames))
           ;; ERT wants the first recorded frame to be close to the original
           ;; signal site (usually `ert-fail' or `signal'), not the handler
           ;; plumbing around it.
           (frames
             (or (member-if
                  (lambda (fr)
                    (let ((fun (car fr)))
                      (and (symbolp fun)
                           (or (eq fun 'ert-fail) (eq fun 'signal)))))
                  frames)
                 frames))
           ;; Avoid huge/cyclic arguments from SBCL's frame-call reconstruction:
           ;; only keep args for frames we expect ERT to care about.
           (frames
             (mapcar
              (lambda (fr)
                (let ((fun (car fr)))
                  (if (and (symbolp fun) (or (eq fun 'signal) (eq fun 'ert-fail)))
                      fr
                      (cons fun nil))))
              frames))
           ;; SBCL may omit `ert-fail' due to tail call elimination.  Upstream
           ;; `ert-test-run-tests-batch-expensive' expects the batch backtrace
           ;; to include an `ert-fail(DATA)' frame, so synthesize it from the
           ;; corresponding `(signal 'ert-test-failed (list DATA))' call.
           (frames
             (let ((sig (car frames)))
               (if (and (consp sig)
                        (eq (car sig) 'signal)
                        (consp (cdr sig))
                        (eq (cadr sig) 'ert-test-failed)
                        (consp (cddr sig))
                        (let ((data (caddr sig)))
                          (and (listp data) (consp data) (null (cdr data)))))
                   (let ((data (car (caddr sig))))
                     (cons (cons 'ert-fail (list data)) frames))
                   frames))))
      (cons (cons 'backtrace-get-frames nil) frames)))
  #-sbcl
  (list (cons 'backtrace-get-frames nil)
        (cons 'signal nil)))

(cl:defun backtrace-frame-fun (frame)
  "Bring-up subset of ELisp `backtrace-frame-fun'."
  (cond
   ((consp frame) (car frame))
   ((symbolp frame) frame)
   (t nil)))

(cl:defun backtrace-frame-args (frame)
  "Bring-up subset of ELisp `backtrace-frame-args'."
  (cond
   ((consp frame) (cdr frame))
   (t nil)))

(cl:defun backtrace-to-string (frames)
  "Bring-up subset of ELisp `backtrace-to-string'."
  (with-output-to-string (out)
    (dolist (frame frames)
      (let ((fun (backtrace-frame-fun frame))
            (args (backtrace-frame-args frame)))
        (write-string "  " out)
        (write-string (prin1-to-string fun) out)
        (write-char #\( out)
        (cond
         ((null args) nil)
         ((listp args)
          (loop for arg in args
                for firstp = t then nil do
                  (unless firstp (write-char #\Space out))
                  (write-string (prin1-to-string arg) out)))
         (t
          (write-string (prin1-to-string args) out)))
        (write-char #\) out)
        (write-char #\Newline out)))))

(cl:defun macroexp-file-name ()
  "Stub for ELisp `macroexp-file-name'."
  nil)

(cl:defun macroexp-copyable-p (exp)
  "Bring-up subset of ELisp `macroexp-copyable-p'."
  (cond
   ;; In upstream `macroexp.el` this is (or (symbolp exp) (macroexp-const-p exp)).
   ;; We keep it self-contained to avoid pulling in the full macroexp const
   ;; machinery just to unblock `pcase-let*` expansion during startup.
   ((consp exp)
    (or (eq (car exp) 'quote)
        (and (eq (car exp) 'function)
             (consp (cdr exp))
             (symbolp (cadr exp)))))
   (t t)))

(cl:defvar macroexpand-all-environment nil)

(cl:defun %macroexpand-all--normalize-lambda-list (lambda-list)
  (labels ((rw (xs)
             (cond
              ((null xs) nil)
              ;; `destructuring-bind' doesn't understand &body in all lisps;
              ;; treat it as &rest for our bring-up needs.
              ((and (consp xs) (eq (car xs) '&body))
               (cons '&rest (rw (cdr xs))))
              (t (cons (car xs) (rw (cdr xs)))))))
    (rw lambda-list)))

(cl:defun %macroexpand-all--strip-environment (lambda-list)
  "Return (values LAMBDA-LIST* ENV-VAR).

If LAMBDA-LIST contains &environment VAR, remove it and return VAR."
  (let ((out nil)
        (env-var nil))
    (loop while lambda-list do
      (let ((x (pop lambda-list)))
        (cond
         ((eq x '&environment)
          (setf env-var (pop lambda-list)))
         (t
          (push x out)))))
    (cl:values (nreverse out) env-var)))

(cl:defun %macroexpand-all--macro-arg-bindings (lambda-list args)
  "Build a LET binding list for a macro lambda list and an argument list.

This is intentionally a small subset sufficient for bring-up; it supports:
- required args (symbols),
- &optional (symbols only; defaults to NIL),
- &rest / &body (single symbol; binds remaining args list)."
  (let ((bindings nil)
        (mode :required))
    (labels ((emit (var value)
               (unless (symbolp var)
                 (cl:error "ELISP:MACROEXPAND-ALL unsupported macro var: ~S" var))
               (push (list var value) bindings)))
      (loop while lambda-list do
        (let ((x (pop lambda-list)))
          (cond
           ((eq x '&optional)
            (setf mode :optional))
           ((or (eq x '&rest) (eq x '&body))
            (let ((rest-var (pop lambda-list)))
              (emit rest-var args)
              (setf args nil)
              (setf lambda-list nil)))
           ((or (eq x '&key) (eq x '&allow-other-keys) (eq x '&aux))
            (cl:error "ELISP:MACROEXPAND-ALL macro lambda-list keyword unsupported: ~S" x))
           ((consp x)
            (cl:error "ELISP:MACROEXPAND-ALL destructuring macro args unsupported: ~S" x))
           (t
            (case mode
              (:required (emit x (if (consp args) (pop args) nil)))
              (:optional (emit x (if (consp args) (pop args) nil)))
              (otherwise
               (cl:error "ELISP:MACROEXPAND-ALL internal mode bug: ~S" mode))))))))
      (nreverse bindings)))

(cl:defun %macroexpand-all--macroexpand-1-local (form env)
  "Try to expand FORM using ENV (a cl-macrolet-style binding list).

Return (values EXPANDED EXPANDEDP)."
  (when (and (consp form) (symbolp (car form)) (listp env))
    (let ((binding (find (car form) env :key #'car :test #'eq)))
      (when (and binding (consp binding) (symbolp (car binding)))
        (destructuring-bind (name lambda-list &rest body) binding
          (declare (cl:ignore name))
          (let* ((lambda-list (%macroexpand-all--normalize-lambda-list lambda-list)))
            (multiple-value-bind (lambda-list env-var)
                (%macroexpand-all--strip-environment lambda-list)
              (let* ((args (cdr form))
                     (arg-bindings (%macroexpand-all--macro-arg-bindings lambda-list args))
                     (env-bindings (if env-var (list (list env-var env)) nil))
                     (expanded
                       (cl:eval
                        `(let ,(append env-bindings arg-bindings)
                           ,(macroexp-progn body)))))
                (cl:values expanded t))))))))
  (cl:values form nil))

(cl:defun %macroexpand-all--macroexpand-1 (form env)
  (multiple-value-bind (expanded expandedp)
      (%macroexpand-all--macroexpand-1-local form env)
    (if expandedp
        (cl:values expanded t)
        (cl:macroexpand-1 form (and (not (listp env)) env)))))

(cl:defun macroexp-progn (body)
  "Bring-up subset of ELisp `macroexp-progn'."
  (cond
   ((null body) nil)
   ((null (cdr body)) (car body))
   (t (cons 'progn body))))

(cl:defmacro if-let (bindings then &optional else)
  "Bring-up subset of subr-x `if-let'."
  (let ((vars (mapcar #'car bindings)))
    `(let* ,bindings
       (if (and ,@vars) ,then ,else))))

(cl:defmacro when-let (bindings &body body)
  "Bring-up subset of subr-x `when-let'."
  (let ((vars (mapcar #'car bindings)))
    `(let* ,bindings
       (when (and ,@vars)
         ,@(or body '(nil))))))

(cl:defmacro pcase (expr &rest clauses)
  "Bring-up subset of ELisp `pcase'.

This is a compatibility stub for early bootstrapping. It supports:
- `_` (default)
- (pred FN)
- (or PAT1 PAT2 ...) by expanding into multiple clauses.

If no clause matches, returns nil."
  (labels ((expand-or (pat body)
             (cond
              ((and (consp pat) (eq (car pat) 'or))
               (mapcan (lambda (p) (expand-or p body)) (cdr pat)))
              (t (list (cons pat body))))))
    (let* ((expanded
             (mapcan
              (lambda (clause)
                (destructuring-bind (pat &rest body) clause
                  (expand-or pat body)))
              clauses))
           (has-default (some (lambda (cl) (eq (car cl) '_)) expanded))
           (final (if has-default expanded (append expanded (list (list '_ nil))))))
      `(pcase-exhaustive ,expr ,@final))))

(cl:defmacro pcase-exhaustive (expr &rest clauses)
  "Bring-up subset of ELisp `pcase-exhaustive'.

Supports a small set of patterns used by upstream ERT:
- `_` (default)
- (pred FN)
- quoted constants (e.g. 'nil)
- keyword constants (e.g. :failed)
- backquote templates using `\, and `\,@."
  (let ((v (gensym "PCASE-"))
        (done (gensym "PCASE-DONE-")))
    (labels ((test-form (pattern value-sym)
               (cond
                ((and (consp pattern) (eq (car pattern) 'pred) (= (length pattern) 2))
                 (let ((pred (cadr pattern)))
                   `(,pred ,value-sym)))
                ((and (consp pattern) (eq (car pattern) 'quote) (= (length pattern) 2))
                 (let ((k (cadr pattern)))
                   `(elisp:equal ,value-sym ',k)))
                ((and (symbolp pattern)
                      (eq (symbol-package pattern) (find-package "KEYWORD")))
                 `(eql ,value-sym ,pattern))
                ((null pattern)
                 `(null ,value-sym))
                (t
                 (cl:error "ELISP:PCASE-EXHAUSTIVE unsupported OR subpattern: ~S" pattern)))))
      `(let ((,v ,expr))
         (block ,done
           ,@(mapcar
              (lambda (clause)
                (destructuring-bind (pattern &rest body) clause
                  (cond
                   ((eq pattern '_)
                    `(return-from ,done (progn ,@body)))
                   ((and (consp pattern) (eq (car pattern) 'or))
                    `(when (or ,@(mapcar (lambda (p) (test-form p v)) (cdr pattern)))
                       (return-from ,done (progn ,@body))))
                   ((and (consp pattern) (eq (car pattern) 'pred) (= (length pattern) 2))
                    (let ((pred (cadr pattern)))
                      `(when (,pred ,v)
                         (return-from ,done (progn ,@body)))))
                   ((and (consp pattern) (eq (car pattern) 'quote) (= (length pattern) 2))
                    (let ((k (cadr pattern)))
                      `(when (elisp:equal ,v ',k)
                         (return-from ,done (progn ,@body)))))
                   ((and (symbolp pattern)
                         (eq (symbol-package pattern) (find-package "KEYWORD")))
                    `(when (eql ,v ,pattern)
                       (return-from ,done (progn ,@body))))
                   ((%pcase--bq-form-p pattern)
                    (let ((tmp (gensym "PCASE-TMP-"))
                          (thunk (gensym "PCASE-THUNK-")))
                      (multiple-value-bind (ll checks _vars)
                          (%pcase--template->lambda-list (cadr pattern))
                        (declare (cl:ignore _vars))
                        `(let ((,tmp ,v)
                               (,thunk nil))
                           (handler-case
                               ,(cond
                                  ;; CL:DESTRUCTURING-BIND requires a list lambda
                                  ;; list; for atomic templates like `t` our
                                  ;; template->lambda-list returns a single
                                  ;; binding symbol.
                                  ((symbolp ll)
                                   `(let ((,ll ,tmp))
                                      (when (and ,@checks)
                                        (setf ,thunk (lambda () (progn ,@body))))))
                                  ;; Future-proofing: treat vector templates as a
                                  ;; mismatch for now.
                                  ((vectorp ll)
                                   nil)
                                  (t
                                   `(destructuring-bind ,ll ,tmp
                                      (when (and ,@checks)
                                        (setf ,thunk (lambda () (progn ,@body)))))))
                             (cl:error () (setf ,thunk nil)))
                           (when ,thunk
                             (return-from ,done (cl:funcall ,thunk)))))))
                   ((null pattern)
                    `(when (null ,v)
                       (return-from ,done (progn ,@body))))
                   (t
                    (cl:error "ELISP:PCASE-EXHAUSTIVE unsupported pattern: ~S" pattern)))))
              clauses)
           (error "pcase-exhaustive: no match for %S" ,v))))))

(cl:defun macroexp--fgrep (bindings sexp)
  "Bring-up subset of `macroexp--fgrep'.

Return non-nil if any bound symbols from BINDINGS appear in SEXP.
This is sufficient for `letrec' in `lisp/subr.el' during ERT bring-up."
  (let ((syms (mapcar #'car bindings)))
    (labels ((seen (x)
               (cond
                ((null x) nil)
                ((symbolp x) (and (member x syms :test #'eq) t))
                ((atom x) nil)
                ((and (consp x) (eq (car x) 'quote)) nil)
                (t (or (seen (car x)) (seen (cdr x)))))))
      (seen sexp))))

(cl:defun macroexpand-all (form &optional env)
  "Bring-up subset of ELisp `macroexpand-all'."
  (let ((macroexpand-all-environment env)
        (seen (cl:make-hash-table :test 'eq)))
    (labels ((callable-expander-p (x)
               (or (cl:functionp x) (symbolp x)))
             (env-expander (sym)
               (when (listp env)
                 (let ((b (assoc sym env :test #'eq)))
                   (when (and b (consp b) (callable-expander-p (cdr b)))
                     (cdr b)))))
             (expand-1 (x)
               ;; Some ELisp "special operators" are implemented as CL macros in
               ;; clemacs for pragmatic bootstrapping.  `macroexpand-all' must
               ;; treat them as non-macros, otherwise deep expansion can rewrite
               ;; them in the wrong lexical environment (e.g. `setq' inside ERT's
               ;; nested `should' expansions).
               (when (and (consp x) (symbolp (car x)))
                 (case (car x)
                   ((setq)
                    (return-from expand-1 (cl:values x nil)))
                   ((function)
                    ;; In upstream ELisp, `function' is a special operator, but
                    ;; `cl-flet' / `cl-labels' install an ENV expander for it.
                    (unless (env-expander 'function)
                      (return-from expand-1 (cl:values x nil))))))
               ;; Emacs-style `macroexpand-all-environment`: an alist mapping
               ;; symbols to "expanders" (used by cl-labels to rewrite local
               ;; function references like (rec ...) and (function rec)).
               (when (and (consp x) (symbolp (car x)))
                 (let ((expander (env-expander (car x))))
                   (when expander
                     (cond
                      ;; Only expand (function F) (1 arg).
                      ((and (eq (car x) 'function) (consp (cdr x)) (null (cddr x)))
                       (return-from expand-1
                         (cl:values (funcall expander (cadr x)) t)))
                      (t
                       (return-from expand-1
                         (cl:values (cl:apply expander (cdr x)) t)))))))
               (%macroexpand-all--macroexpand-1 x env))
             (expand-loop (x)
               (let ((cur x)
                     (expandedp t)
                     (guard 0))
                 (loop while expandedp do
                   (incf guard)
                   (when (> guard 200)
                     (cl:error "ELISP:MACROEXPAND-ALL appears to loop on: ~S" cur))
                   (multiple-value-bind (next nextp) (expand-1 cur)
                     (setf cur next
                           expandedp nextp)))
                 cur))
             (rw (x)
               (cond
                ((atom x) x)
                ((gethash x seen) x)
                (t
                 (setf (gethash x seen) t)
                 (let ((x (expand-loop x)))
                   (cond
                    ((atom x) x)
                    ;; Do not macroexpand under QUOTE.
                    ((and (consp x) (eq (car x) 'quote) (consp (cdr x)) (null (cddr x)))
                     x)
                    ;; Expand under FUNCTION only far enough to let ENV rewrite
                    ;; (function F) references (cl-labels); don't traverse inside
                    ;; arbitrary function objects.
                    ((and (consp x) (eq (car x) 'function) (consp (cdr x)) (null (cddr x)))
                     x)
                    ;; General cons rewrite: preserve dotted lists.
                    (t (cons (rw (car x)) (rw (cdr x))))))))))
      (rw form))))

;; Upstream ERT exposes `skip-when' and `skip-unless' inside `ert-deftest'
;; bodies.  For bring-up, also provide them as global macros so test bodies
;; that close over them in lambdas still macroexpand under SBCL.
(cl:defmacro skip-when (form)
  `(ert--skip-when ,form))

(cl:defmacro skip-unless (form)
  `(ert--skip-unless ,form))

(cl:defmacro condition-case (var bodyform &rest handlers)
  "Bring-up subset of ELisp `condition-case'.

Binds VAR (when non-nil) to an ELisp-style error datum:
  (ERROR-SYMBOL . DATA)."
  (let* ((tag (gensym "CC-CATCH-"))
         (out (gensym "CC-OUT-"))
         (e (gensym "CC-E-"))
         (err (or var (gensym "CC-ERR-")))
         (success-clause (find :success handlers :key #'car))
         (error-clauses (remove :success handlers :key #'car)))
    (labels ((matchp-form (types sym)
               (cond
                ((eq types t) t)
                ((and (symbolp types) (eq types 'error)) t)
                ((symbolp types)
                 `(let ((conds (get ,sym 'error-conditions)))
                    (and (listp conds) (member ',types conds :test #'eq))))
                ((consp types)
                 `(let ((conds (get ,sym 'error-conditions)))
                    (and (listp conds)
                         (some (lambda (t0) (member t0 conds :test #'eq)) ',types))))
                (t nil)))
             (expand-clauses (err-sym)
               (let ((sym `(car ,err-sym)))
                 `(cond
                   ,@(mapcar
                      (lambda (clause)
                        (destructuring-bind (types &rest body) clause
                          `(,(matchp-form types sym)
                            ,(if var
                                 `(let ((,var ,err-sym)) (progn ,@body))
                                 `(progn ,@body)))))
                      error-clauses)
                   ;; No matching handler: re-signal the original error.
                   (t (signal (car ,err-sym) (cdr ,err-sym)))))))
      `(let ((,out
              (catch ',tag
                (cl:handler-bind
                    ((elisp-signal
                       (lambda (,e)
                         (throw ',tag
                           (list :err
                                 (cons (elisp-signal-symbol ,e)
                                       (elisp-signal-data ,e))))))
                     (cl:error
                       (lambda (,e)
                         (unless (typep ,e 'elisp-signal)
                           (throw ',tag
                             (list :err
                                   (cond
                                    ((typep ,e 'arithmetic-error)
                                     (cons 'arith-error (list ,e)))
                                    (t
                                     (cons 'error (list ,e))))))))))
                  (list :ok ,bodyform)))))
         (cond
          ((and (consp ,out) (eq (car ,out) :ok))
           (let ((res (cadr ,out)))
             ,(if success-clause
                  (destructuring-bind (_ &rest body) success-clause
                    (declare (cl:ignore _))
                    (if var
                        `(let ((,var res)) (progn ,@body))
                        `(progn ,@body)))
                  'res)))
          ((and (consp ,out) (eq (car ,out) :err))
           (let ((,err (cadr ,out)))
             ,(expand-clauses err)))
          (t ,out))))))

(define-condition elisp-signal (cl:error)
  ((symbol :initarg :symbol :reader elisp-signal-symbol)
   (data :initarg :data :reader elisp-signal-data)))

(cl:defun signal (error-symbol data)
  "Bring-up subset of ELisp `signal'.

ERROR-SYMBOL is an error condition name (a symbol) and DATA is a list of
arguments. We map this to a CL condition so `condition-case' can recover
the original (SYMBOL . DATA) pair."
  (unless (symbolp error-symbol)
    (cl:error "ELISP:SIGNAL expected symbol, got: ~S" error-symbol))
  (unless (listp data)
    (cl:error "ELISP:SIGNAL expected list data, got: ~S" data))
  (cl:error 'elisp-signal :symbol error-symbol :data data))

(cl:defun %format-message (fmt args)
  "Very small subset of ELisp `format' used for early error messages.

  Supports: %s, %S, %d, %x, %c, and %%."
  (unless (stringp fmt)
    (when (uiop:getenv "CLEMACS_DEBUG_FORMAT_BAD_FMT")
      (let ((path "build/clemacs/tmp/format-bad-fmt.out"))
        (ensure-directories-exist path)
        (with-open-file (out path
                             :direction :output
                             :if-exists :append
                             :if-does-not-exist :create)
          (cl:format out "~&[format] bad fmt: ~S ; args=~S~%" fmt args)
          #+sbcl
          (sb-debug:print-backtrace :stream out :count 80)
          (finish-output out))))
    (cl:error "ELISP:ERROR expects a string format, got: ~S" fmt))
  (let* ((fmt-s (%elisp-string->cl-string fmt))
         (i 0)
         (n (length fmt-s))
         (rest args)
         (codes (make-array 0 :element-type 'integer :adjustable t :fill-pointer 0))
         (need-multibyte nil))
    (labels ((emit-code (code)
               (vector-push-extend code codes)
               (when (or (%raw-byte-char-code-p code) (>= code 128))
                 (setf need-multibyte t)))
             (emit-cl-string (s)
               (dotimes (j (length s))
                 (emit-code (char-code (char s j)))))
             (emit-obj-princ (o)
               (cond
                ((stringp o) (emit-cl-string (%elisp-string->cl-string o)))
                (t (emit-cl-string (cl:princ-to-string o)))))
             (emit-obj-prin1 (o)
               (emit-cl-string (%elisp-string->cl-string (prin1-to-string o))))
             (emit-dec (o)
               (emit-cl-string (cl:princ-to-string o)))
             (emit-hex (o)
               (emit-cl-string
                (cl:string-downcase
                 (cl:format nil "~x"
                            (cond
                             ((integerp o) o)
                             ((cl:characterp o) (char-code o))
                             (t o))))))
             (emit-c (o)
               (cond
                ((integerp o) (emit-code o))
                ((cl:characterp o) (emit-code (char-code o)))
                (t
                 (let ((s (cl:princ-to-string o)))
                   (when (> (length s) 0)
                     (emit-code (char-code (char s 0))))))))
             (finish ()
               (if (not need-multibyte)
                   (let ((out (%make-unibyte-string (length codes))))
                     (dotimes (k (length codes))
                       (setf (aref out k) (aref codes k)))
                     out)
                   (let ((out (cl:make-string (length codes))))
                     (dotimes (k (length codes))
                       (setf (char out k) (%elisp-code->char (aref codes k))))
                     out))))
      (loop while (< i n) do
        (let ((ch (char fmt-s i)))
          (if (char= ch #\%)
              (progn
                (incf i)
                (when (>= i n)
                  (emit-code (char-code #\%))
                  (return))
                (let* ((code (char fmt-s i))
                       (arg-present (consp rest))
                       (arg (if arg-present (pop rest) nil)))
                  (case code
                    (#\% (emit-code (char-code #\%)))
                    (#\s (when arg-present (emit-obj-princ arg)))
                    (#\S (when arg-present (emit-obj-prin1 arg)))
                    (#\d (when arg-present (emit-dec arg)))
                    (#\x (when arg-present (emit-hex arg)))
                    (#\c (when arg-present (emit-c arg)))
                    (otherwise
                     (emit-code (char-code #\%))
                     (emit-code (char-code code))))))
              (emit-code (char-code ch))))
        (incf i))
      (finish))))

(cl:defun format-message (fmt &rest args)
  "Bring-up subset of ELisp `format-message'."
  (%format-message fmt args))

(cl:defun format (fmt &rest args)
  "Bring-up subset of ELisp `format'."
  (%format-message fmt args))

(cl:defun characterp (x)
  "ELisp-ish `characterp'.

In Emacs, characters are represented as integers."
  (or (cl:characterp x)
      (and (integerp x) (<= 0 x #x3fffff) t)))

(cl:defun error (fmt &rest args)
  "Signal an ELisp-style `error' with DATA = (MESSAGE).

This is intentionally not CL:ERROR; it raises an `elisp-signal' so ELisp
`handler-bind' and `condition-case' can recover the (SYMBOL . DATA) pair."
  (let ((msg (if args (%format-message fmt args) fmt)))
    (signal 'error (list msg))))

(cl:defun %handler-bind-match-p (types err)
  (let ((sym (car err)))
    (cond
     ((eq types t) t)
     ((symbolp types)
      (or (eq sym types)
          ;; Treat `error' as a catch-all for ELisp signals.
          (eq types 'cl:error)
          (eq types 'error)))
     ((consp types)
      (some (lambda (t0) (%handler-bind-match-p t0 err)) types))
     (t nil))))

(cl:defmacro handler-bind (bindings &body body)
  "Bring-up subset of ELisp `handler-bind' (cl-lib style).

Unlike CL:HANDLER-BIND, handlers receive an ELisp-style error datum:
  (ERROR-SYMBOL . DATA)."
  (let ((handlers
          (mapcar
           (lambda (b)
             (destructuring-bind (types handler) b
               (let ((c (gensym "C"))
                     (err (gensym "ERR")))
                 `(elisp-signal
                   (lambda (,c)
                     (let ((,err (cons (elisp-signal-symbol ,c) (elisp-signal-data ,c))))
                       (when (%handler-bind-match-p ',types ,err)
                         (funcall ,handler ,err))))))))
           bindings)))
    `(cl:handler-bind
         ,handlers
       ,@body)))

(cl:defun handler--bind (thunk &rest args)
  "Implementation helper for `lisp/subr.el' `handler-bind'.

SUBR's macro expands to:
  (handler--bind (lambda () ...) CONDS1 HANDLER1 CONDS2 HANDLER2 ...)

Where each HANDLER is a function that takes one argument: the error object.
In clemacs, the error object is represented as (ERROR-SYMBOL . DATA)."
  (unless (functionp thunk)
    (error "ELISP:HANDLER--BIND expects a function thunk, got: %S" thunk))
  (unless (evenp (length args))
    (error "ELISP:HANDLER--BIND expects an even number of args, got: %S" args))
  (cl:handler-bind
      ((elisp-signal
         (lambda (c)
           (let ((err (cons (elisp-signal-symbol c) (elisp-signal-data c))))
             (loop for (types handler) on args by #'cddr do
               (when (%handler-bind-match-p types err)
                 (funcall handler err)))))))
    (funcall thunk)))

(define-condition quit (cl:error) ())

(cl:defmacro letrec (bindings &body body)
  "Bring-up subset of ELisp `letrec'.

Supports the common pattern of a self-referential closure (used by ERT)."
  (let ((vars (mapcar #'car bindings)))
    `(let ,(mapcar (lambda (v) (list v nil)) vars)
       ,@(mapcar (lambda (b) (list 'setq (car b) (cadr b))) bindings)
       ,@body)))

(defvar *special-operator-subrs* nil)

(cl:defun indirect-function (thing &optional noerror)
  "Bring-up subset of ELisp `indirect-function'."
  (handler-case
      (cond
       ((symbolp thing)
        (let ((seen nil)
              (cur thing))
          (loop
            (when (member cur seen :test #'eq)
              (error "ELISP:INDIRECT-FUNCTION circular definition: ~S" thing))
            (push cur seen)
            (let ((special (gethash cur *special-operator-subrs*)))
              (when special
                (return special)))
            (let ((def (symbol-function cur)))
              (cond
               ((null def)
                (return nil))
               ((and (symbolp def) (not (eq def cur)))
                (setf cur def))
               (t
                (return def)))))))
       ((functionp thing) thing)
       (t (error "ELISP:INDIRECT-FUNCTION bad value: ~S" thing)))
    (cl:error (e)
      (if noerror nil (cl:error e)))))

(defstruct elisp-subr
  (arity (cons 0 0)))

(defparameter *special-operator-subrs*
  (let ((ht (cl:make-hash-table :test 'eq)))
    ;; Enough to make upstream ERT's `ert--special-operator-p' treat these
    ;; as special operators (so `should' can handle quoted forms).
    (setf (gethash 'cl:quote ht) (make-elisp-subr :arity (cons 1 'unevalled)))
    (setf (gethash 'cl:function ht) (make-elisp-subr :arity (cons 1 'unevalled)))
    (setf (gethash 'cl:progn ht) (make-elisp-subr :arity (cons 0 'unevalled)))
    (setf (gethash 'cl:if ht) (make-elisp-subr :arity (cons 2 'unevalled)))
    (setf (gethash 'cl:let ht) (make-elisp-subr :arity (cons 1 'unevalled)))
    (setf (gethash 'cl:let* ht) (make-elisp-subr :arity (cons 1 'unevalled)))
    (setf (gethash 'cl:catch ht) (make-elisp-subr :arity (cons 1 'unevalled)))
    (setf (gethash 'cl:throw ht) (make-elisp-subr :arity (cons 2 'unevalled)))
    (setf (gethash 'cl:unwind-protect ht) (make-elisp-subr :arity (cons 1 'unevalled)))
    ht))

(cl:defun subrp (object)
  "Bring-up subset of ELisp `subrp'."
  (and (typep object 'elisp-subr) t))

(cl:defun subr-arity (object)
  "Bring-up subset of ELisp `subr-arity'."
  (when (typep object 'elisp-subr)
    (elisp-subr-arity object)))

(cl:defun %mode-hook-symbol (mode)
  (intern (concat (symbol-name mode) "-hook")))

(cl:defun %mode-map-symbol (mode)
  (intern (concat (symbol-name mode) "-map")))

(cl:defun %key-id (key)
  (cond
   ((stringp key) key)
   ((vectorp key) (write-to-string key :escape t))
   ((characterp key) (string key))
   ((integerp key) (cl:format nil "#<keycode ~D>" key))
   (t (write-to-string key :escape t))))

(cl:defun %key-event-description (event)
  (cond
   ((integerp event)
    (cond
     ((= event 127) "DEL")
     ((= event 27) "ESC")
     ((= event 13) "RET")
     ((= event 9) "TAB")
     ((= event 32) "SPC")
     ((and (<= 0 event) (< event 32))
      (cl:format nil "C-~A" (string (code-char (+ event 64)))))
     (t
      (string (code-char event)))))
   ((characterp event) (string event))
   ((symbolp event) (symbol-name event))
   (t (princ-to-string event))))

(cl:defun key-description (keys &optional _noangles)
  "Bring-up subset of ELisp `key-description'."
  (declare (cl:ignore _noangles))
  (labels ((emit (seq)
             (with-output-to-string (out)
               (loop for i from 0 for ev in seq do
                 (when (> i 0) (write-char #\Space out))
                 (write-string (%key-event-description ev) out)))))
    (cond
     ((stringp keys)
      (emit (loop for ch across keys collect (char-code ch))))
     ((vectorp keys)
      (emit (loop for i from 0 below (length keys) collect (aref keys i))))
     ((consp keys) (emit keys))
     (t (%key-event-description keys)))))

(cl:defun define-key (keymap key definition)
  "Minimal stub for ELisp `define-key' on `elisp-keymap' objects."
  (let ((km (if (symbolp keymap) (symbol-value keymap) keymap)))
    (unless (typep km 'elisp-keymap)
      (error "ELISP:DEFINE-KEY expected keymap, got: ~S" keymap))
    (setf (gethash (%key-id key) (elisp-keymap-table km)) definition)
    definition))

(cl:defun define-abbrev-table (name defs &optional _docstring &rest _rest)
  "Bring-up stub for ELisp `define-abbrev-table'."
  (declare (cl:ignore _docstring _rest))
  (unless (symbolp name)
    (error "ELISP:DEFINE-ABBREV-TABLE expected symbol, got: ~S" name))
  ;; During bring-up we ignore DEFS and represent abbrev tables as plain hash
  ;; tables.  This is enough for mode files that only need the variable bound.
  (unless (or (null defs) (listp defs))
    (error "ELISP:DEFINE-ABBREV-TABLE expected defs list or nil, got: ~S" defs))
  (let ((tbl (cl:make-hash-table :test 'cl:equal)))
    (set name tbl)
    tbl))

(cl:defmacro define-derived-mode (child _parent _name &optional docstring &rest _body)
  "Bring-up subset of ELisp `define-derived-mode'.

For now we:
- create CHILD-hook and CHILD-map variables (if not already bound),
- define a no-op mode function CHILD.

This is sufficient for many shipped Elisp files to load; it is not a full
major-mode implementation."
  (declare (cl:ignore _parent _name _body))
  (let ((hook (%mode-hook-symbol child))
        (map (%mode-map-symbol child)))
    `(progn
       (cl:defvar ,hook nil)
       (cl:defvar ,map (make-elisp-keymap))
       (defun ,child (&rest _args)
         ,@(when (stringp docstring) (list docstring))
         (declare (cl:ignore _args))
         nil)
       ',child)))

(cl:defmacro easy-menu-define (symbol _keymap _doc menu)
  "Bring-up stub for ELisp `easy-menu-define'."
  (declare (cl:ignore _keymap _doc))
  `(progn
     (cl:defvar ,symbol ,menu)
     ',symbol))

(cl:defun define-button-type (&rest _args)
  "Bring-up stub for ELisp `define-button-type'."
  (declare (cl:ignore _args))
  nil)

(cl:defun insert-text-button (label &rest _properties)
  "Bring-up stub for ELisp `insert-text-button'.

We currently ignore PROPERTIES and just insert LABEL, returning the start
position."
  (declare (cl:ignore _properties))
  (let ((begin (point)))
    (insert label)
    begin))

(cl:defun add-hook (hook function &optional append _local)
  "Bring-up subset of ELisp `add-hook'.

HOOK is a symbol naming a hook variable whose value is a list of functions."
  (declare (cl:ignore _local))
  (unless (symbolp hook)
    (error "ELISP:ADD-HOOK expected a hook symbol, got: ~S" hook))
  (let ((cur (if (cl:boundp hook) (symbol-value hook) nil)))
    (unless (listp cur)
      (set hook nil)
      (setf cur nil))
    (unless (member function cur :test #'equal)
      (set hook (if append (append cur (list function)) (cons function cur)))))
  t)

(cl:defun remove-hook (hook function &optional _local)
  "Bring-up subset of ELisp `remove-hook'."
  (declare (cl:ignore _local))
  (unless (symbolp hook)
    (error "ELISP:REMOVE-HOOK expected a hook symbol, got: ~S" hook))
  (when (cl:boundp hook)
    (let ((cur (symbol-value hook)))
      (when (listp cur)
        (set hook (remove function cur :test #'equal)))))
  t)

(cl:defun run-hooks (&rest hooks)
  "Bring-up subset of ELisp `run-hooks'."
  (dolist (hook hooks)
    (when (and (symbolp hook) (cl:boundp hook))
      (let ((cur (symbol-value hook)))
        (when (listp cur)
          (dolist (fn cur)
            (ignore-errors (funcall fn)))))))
  nil)

(cl:defun add-to-list (list-var element &optional append _compare-fn)
  "Bring-up subset of ELisp `add-to-list'."
  (declare (cl:ignore _compare-fn))
  (unless (symbolp list-var)
    (error "ELISP:ADD-TO-LIST expected a symbol, got: ~S" list-var))
  (let ((cur (if (cl:boundp list-var) (symbol-value list-var) nil)))
    (unless (listp cur)
      (set list-var nil)
      (setf cur nil))
    (unless (member element cur :test #'equal)
      (set list-var (if append (append cur (list element)) (cons element cur)))))
  t)

(cl:defun make-keymap ()
  "Extremely small stub for ELisp `make-keymap'."
  (make-elisp-keymap))

(cl:defun make-sparse-keymap (&optional _name)
  "Extremely small stub for ELisp `make-sparse-keymap'."
  (declare (cl:ignore _name))
  (make-elisp-keymap))

(cl:defun make-vector (length init)
  "ELisp-ish MAKE-VECTOR."
  (make-array length :initial-element init))

(cl:defun aset (array idx value)
  "ELisp-ish ASET."
  (setf (aref array idx) value)
  value)

(cl:defun set-keymap-parent (keymap parent)
  "Extremely small stub for ELisp `set-keymap-parent'."
  (unless (typep keymap 'elisp-keymap)
    (error "ELISP:SET-KEYMAP-PARENT expected a keymap, got: ~S" keymap))
  (when (and parent (not (typep parent 'elisp-keymap)))
    (error "ELISP:SET-KEYMAP-PARENT expected a keymap parent, got: ~S" parent))
  (setf (elisp-keymap-parent keymap) parent)
  keymap)

(cl:defun use-global-map (keymap)
  "Extremely small stub for ELisp `use-global-map'."
  (setf *global-map* keymap)
  keymap)

(cl:defun current-global-map ()
  "Extremely small stub for ELisp `current-global-map'."
  *global-map*)

(cl:defun make-obsolete (&rest _args)
  "Stub for ELisp `make-obsolete'."
  (declare (cl:ignore _args))
  nil)

(cl:defmacro defconst (name value &optional docstring)
  "ELisp-ish DEFCONST (currently just DEFPARAMETER).

If NAME lives in the CL package, ignore the definition."
  (declare (cl:ignore docstring))
  (if (and (symbolp name) (eq (symbol-package name) (find-package "CL")))
      `(progn ',name)
      `(defparameter ,name ,value)))

(defparameter -c-@ 0)

(cl:defmacro with-suppressed-warnings (_spec &body body)
  "Compatibility shim; ignores suppression spec."
  (declare (cl:ignore _spec))
  `(progn ,@body))

(cl:defun set-advertised-calling-convention (&rest _args)
  "Stub for ELisp `set-advertised-calling-convention'."
  (declare (cl:ignore _args))
  nil)

(cl:defun make-obsolete-variable (&rest _args)
  "Stub for ELisp `make-obsolete-variable'."
  (declare (cl:ignore _args))
  nil)

(cl:defmacro defmacro (name lambda-list &body body)
  "Define a macro without mutating CL package symbols.

If NAME lives in the CL package, ignore the definition (this avoids
trying to redefine CL special operators and other locked symbols while
loading upstream ELisp)."
  (if (and (symbolp name) (eq (symbol-package name) (find-package "CL")))
      `(progn ',name)
      (let* ((doc (and body (stringp (car body)) (car body)))
             (doc* (and doc (if (cl:stringp doc) doc (%elisp-string->cl-string doc))))
             (rest (if doc (cdr body) body)))
        `(cl:defmacro ,name ,lambda-list
           ,@(when doc* (list doc*))
           ,@rest))))

(cl:defmacro defun (name lambda-list &body body)
  "Define a function without mutating CL package symbols.

If NAME lives in the CL package, ignore the definition (this avoids
trying to redefine locked symbols while loading upstream ELisp)."
  (if (and (symbolp name) (eq (symbol-package name) (find-package "CL")))
      `(progn ',name)
      (let* ((doc (and body (stringp (car body)) (car body)))
             (doc* (and doc (if (cl:stringp doc) doc (%elisp-string->cl-string doc))))
             (rest (if doc (cdr body) body)))
        `(cl:defun ,name ,lambda-list
           ,@(when doc* (list doc*))
           ,@rest))))

(cl:defmacro defsubst (name lambda-list &body body)
  "ELisp-ish DEFSUBST (currently just DEFUN)."
  `(defun ,name ,lambda-list ,@body))

(cl:defun equal (a b)
  (cond
   ((and (stringp a) (stringp b))
    (cl:string= (string-to-multibyte a) (string-to-multibyte b)))
   ((and (consp a) (consp b))
    (and (equal (car a) (car b))
         (equal (cdr a) (cdr b))))
   ((and (typep a 'elisp-keymap) (typep b 'elisp-keymap))
    (labels ((ht-equal (ha hb)
               (and (= (hash-table-count ha) (hash-table-count hb))
                    (block ok
                      (maphash
                       (lambda (k va)
                         (multiple-value-bind (vb presentp) (gethash k hb)
                           (unless (and presentp (equal va vb))
                             (return-from ok nil))))
                       ha)
                      t))))
      (and (ht-equal (elisp-keymap-table a) (elisp-keymap-table b))
           (equal (elisp-keymap-parent a) (elisp-keymap-parent b)))))
   ((and (vectorp a) (vectorp b))
    (and (= (length a) (length b))
         (loop for i from 0 below (length a)
               always (equal (aref a i) (aref b i)))))
   (t (cl:equal a b))))

(cl:defun type-of (object)
  "ELisp-ish `type-of'.

This deliberately returns coarse ELisp-style type names, not CL's
implementation-specific ones."
  (cond
   ((null object) 'symbol)
   ((symbolp object) 'symbol)
   ((consp object) 'cons)
   ((integerp object) 'integer)
   ((stringp object) 'string)
   ((vectorp object) 'vector)
   ((hash-table-p object) 'hash-table)
   ((typep object 'elisp-char-table) 'char-table)
   (t (cl:type-of object))))

(cl:defun char-table-p (object)
  "Return non-nil if OBJECT is a char-table."
  (typep object 'elisp-char-table))

(cl:defun make-char-table (type &optional init)
  "Return a new char-table.

This is a minimal bring-up implementation: it supports a fixed range of
character codes (0..65535), a parent link, and extra slots."
  (%make-elisp-char-table type init
                          (make-array +char-table-size+ :initial-element nil)
                          (make-array 0 :adjustable t :fill-pointer 0)
                          nil))

(cl:defvar char-script-table (make-char-table 'char-script nil))

(cl:defun set-char-table-parent (table parent)
  "Set TABLE's parent to PARENT and return PARENT."
  (unless (char-table-p table)
    (error "ELISP:set-char-table-parent expects a char-table, got: ~S" table))
  (unless (or (null parent) (char-table-p parent))
    (error "ELISP:set-char-table-parent expects nil or char-table parent, got: ~S"
           parent))
  (setf (elisp-char-table-parent table) parent)
  parent)

(cl:defun char-table-parent (table)
  "Return TABLE's parent, or nil."
  (unless (char-table-p table)
    (error "ELISP:char-table-parent expects a char-table, got: ~S" table))
  (elisp-char-table-parent table))

(cl:defun set-char-table-extra-slot (table n value)
  "Set TABLE's extra slot N to VALUE and return VALUE."
  (unless (char-table-p table)
    (error "ELISP:set-char-table-extra-slot expects a char-table, got: ~S" table))
  (unless (and (integerp n) (<= 0 n))
    (error "ELISP:set-char-table-extra-slot expects non-negative slot index, got: ~S"
           n))
  (let ((extra (elisp-char-table-extra table)))
    (when (<= (length extra) n)
      (adjust-array extra (1+ n) :initial-element nil :fill-pointer (1+ n)))
    (setf (aref extra n) value))
  value)

(cl:defun char-table-extra-slot (table n)
  "Return TABLE's extra slot N."
  (unless (char-table-p table)
    (error "ELISP:char-table-extra-slot expects a char-table, got: ~S" table))
  (unless (and (integerp n) (<= 0 n))
    (error "ELISP:char-table-extra-slot expects non-negative slot index, got: ~S"
           n))
  (let ((extra (elisp-char-table-extra table)))
    (if (< n (length extra)) (aref extra n) nil)))

(cl:defvar *standard-syntax-table* nil)

(cl:defun standard-syntax-table ()
  "Return the global standard syntax table."
  (or *standard-syntax-table*
      (setf *standard-syntax-table* (make-char-table 'syntax-table (cons 0 nil)))))

(cl:defun %syntax-spec-code (spec)
  ;; Mirror Emacs's `syntax_spec_code` mapping for the subset we need during
  ;; early editor-core bring-up.
  (case spec
    (32 0)   ; space
    (46 1)   ; .
    (119 2)  ; w
    (95 3)   ; _
    (40 4)   ; (
    (41 5)   ; )
    (39 6)   ; '
    (34 7)   ; "
    (36 8)   ; $
    (92 9)   ; \
    (47 10)  ; /
    (60 11)  ; <
    (62 12)  ; >
    (64 13)  ; @
    (33 14)  ; !
    (124 15) ; |
    (t nil)))

(defconstant +syntax-flag-prefix+ (ash 1 20))

(cl:defun %syntax-entry-from-spec (syntax)
  (unless (or (unibyte-string-p syntax) (cl:stringp syntax))
    (error "ELISP:modify-syntax-entry expects syntax string, got: ~S" syntax))
  (when (zerop (length syntax))
    (error "ELISP:modify-syntax-entry expects non-empty syntax string"))
  (let* ((spec (aref syntax 0))
         (code (%syntax-spec-code spec)))
    (unless (and code (<= 0 code))
      (error "ELISP:unsupported syntax spec code: ~S" spec))
    (let ((flags 0)
          (matching nil))
      (when (and (or (= code 4) (= code 5)) (>= (length syntax) 2))
        (setf matching (aref syntax 1)))
      (loop for i from 1 below (length syntax) do
        (when (= (aref syntax i) 112) ; "p"
          (setf flags (logior flags +syntax-flag-prefix+))))
      (cons (logior code flags) matching))))

(cl:defun modify-syntax-entry (ch syntax &optional table)
  "Set the syntax entry for CH in TABLE according to SYNTAX.

This is a bring-up subset: it supports the common syntax class letters and
the prefix flag (\"p\")."
  (let* ((code (cond
                ((integerp ch) ch)
                ((characterp ch) (char-code ch))
                (t (error "ELISP:modify-syntax-entry expects character code, got: ~S"
                          ch))))
         (tab (or table (error "ELISP:modify-syntax-entry requires TABLE for now")))
         (entry (%syntax-entry-from-spec syntax)))
    (unless (char-table-p tab)
      (error "ELISP:modify-syntax-entry expects a char-table, got: ~S" tab))
    (%char-table-set tab code entry)
    nil))

(cl:defun %lexical-variable-p (symbol env)
  (multiple-value-bind (kind)
      (sb-cltl2:variable-information symbol env)
    (eq kind :lexical)))

(defvar *elisp-variable-aliases* (cl:make-hash-table :test 'eq))

(cl:defun %resolve-variable-alias (symbol &key (max-hops 16))
  (loop with cur = symbol
        for hop from 0 below max-hops do
          (multiple-value-bind (next presentp)
              (gethash cur *elisp-variable-aliases*)
            (cond
             ((not presentp) (return cur))
             ((not (symbolp next)) (return cur))
             (t (setf cur next))))
        finally
          (return symbol)))

(cl:defun symbol-value (symbol)
  "ELisp-ish SYMBOL-VALUE (respects `defvaralias')."
  (cl:symbol-value (%resolve-variable-alias symbol)))

(cl:defun set (symbol value)
  "ELisp-ish SET (respects `defvaralias')."
  (let ((sym (%resolve-variable-alias symbol)))
    (setf (cl:symbol-value sym) value)
    value))

(cl:defun defvaralias (new-alias base-variable &optional _docstring)
  "ELisp-ish DEFVARALIAS."
  (declare (cl:ignore _docstring))
  (setf (gethash new-alias *elisp-variable-aliases*) base-variable)
  new-alias)

(cl:defun define-obsolete-variable-alias (obsolete-name current-name &optional _since)
  "Stub for ELisp `define-obsolete-variable-alias'."
  (declare (cl:ignore _since))
  (defvaralias obsolete-name current-name)
  obsolete-name)

(cl:defun define-obsolete-function-alias (obsolete-name current-definition &optional _since _docstring)
  "Stub for ELisp `define-obsolete-function-alias'."
  (declare (cl:ignore _since _docstring))
  (defalias obsolete-name current-definition)
  obsolete-name)

(cl:defun autoload (function file &optional _docstring _interactive _type)
  "Stub for ELisp `autoload'.

Stores a non-callable marker in the function cell; calling it will
fail until proper autoload support exists."
  (declare (cl:ignore _docstring _interactive _type))
  (unless (symbolp function)
    (error "ELISP:AUTOLOAD expects a function symbol, got: ~S" function))
  (fset function (list 'autoload file))
  function)

(cl:defun custom-autoload (symbol file &optional _interactive)
  "Bring-up stub for ELisp `custom-autoload'.

Used by `ldefs-boot.el` / `loaddefs.el` to register Customize variables and
functions.  For now, delegate to `autoload` and return SYMBOL."
  (declare (cl:ignore _interactive))
  (autoload symbol file)
  symbol)

(cl:defun symbol-file (_symbol &optional _type)
  "Bring-up stub for ELisp `symbol-file'."
  (declare (cl:ignore _symbol _type))
  nil)

(cl:defmacro with-demoted-errors (_format &rest body)
  "Bring-up subset of ELisp `with-demoted-errors'.

Evaluate BODY, but if an error is signaled, demote it and return nil."
  (declare (cl:ignore _format))
  (let ((err (gensym "ERR")))
    `(condition-case ,err
         (progn ,@body)
       (error nil))))

(cl:defun make-variable-buffer-local (variable)
  "Stub for ELisp `make-variable-buffer-local'."
  variable)

(cl:defun make-local-variable (variable)
  "Bring-up stub for ELisp `make-local-variable'.

We do not model true buffer-local variables yet; this is just enough for
`setq-local' to run without error."
  (unless (symbolp variable)
    (error "ELISP:MAKE-LOCAL-VARIABLE expects a symbol, got: ~S" variable))
  variable)

(cl:defun default-boundp (symbol)
  "Stub for ELisp `default-boundp'.

The \"default\" value is CL's global binding model."
  (cl:boundp (%resolve-variable-alias symbol)))

(cl:defun local-variable-if-set-p (_symbol &optional _buffer)
  "Bring-up subset of ELisp `local-variable-if-set-p'."
  (declare (cl:ignore _symbol _buffer))
  nil)

(cl:defun default-value (symbol)
  "Stub for ELisp `default-value'."
  (cl:symbol-value (%resolve-variable-alias symbol)))

(cl:defun set-default (symbol value)
  "Stub for ELisp `set-default'."
  (let ((sym (%resolve-variable-alias symbol)))
    (setf (cl:symbol-value sym) value)
    value))

(cl:defmacro setq (&environment env &rest pairs)
  (unless (evenp (length pairs))
    (error "ELISP:SETQ expects an even number of arguments"))

  (let ((forms nil))
    (loop for (var val) on pairs by (cl:function cl:cddr) do
      (unless (symbolp var)
        (error "ELISP:SETQ only supports symbol variables, got: ~S" var))
      (push (if (%lexical-variable-p var env)
                `(cl:setq ,var ,val)
                `(set ',var ,val))
            forms))
    `(progn ,@(nreverse forms))))

(cl:defmacro define-minor-mode (name &rest args)
  "Bring-up stub for ELisp `define-minor-mode'.

This only defines the mode variable and a basic toggling function."
  (unless (symbolp name)
    (error "ELISP:DEFINE-MINOR-MODE expects a symbol name, got: ~S" name))
  (let ((doc (and args (stringp (car args)) (pop args))))
    `(progn
       (defvar ,name nil ,doc)
       (defun ,name (&optional arg)
         ,@(when doc (list doc))
         (setq ,name (cond
                      ((null arg) (not ,name))
                      ((integerp arg) (> arg 0))
                      (t arg)))
         ,name))))

(cl:defun fset (symbol definition)
  "Set SYMBOL's function cell to DEFINITION.

Also installs a CL-visible definition when needed so that evaluating ELisp as
CL forms (e.g. calls like (foo ...)) works during bootstrap."
  (when (and (symbolp symbol)
             (eq (symbol-package symbol) (find-package "CL")))
    (return-from fset symbol))
  (setf (gethash symbol *elisp-function-cells*) definition)
  (when (symbolp symbol)
    (cond
     ((and (consp definition) (eq (car definition) 'macro) (functionp (cdr definition)))
      (setf (cl:macro-function symbol) (cdr definition)))
     ((functionp definition)
      (setf (cl:fdefinition symbol) definition))
     ((not (cl:fboundp symbol))
      (setf (cl:fdefinition symbol)
            (lambda (&rest args)
              (cl:apply (%resolve-function definition) args))))))
  symbol)

(cl:defun defalias (symbol definition &optional _docstring)
  "Alias SYMBOL's function definition to DEFINITION."
  (declare (cl:ignore _docstring))
  (when (and (symbolp symbol)
             (eq (symbol-package symbol) (find-package "CL")))
    (return-from defalias symbol))
  (fset symbol definition))

(cl:defmacro while (test &body body)
  "ELisp-ish WHILE."
  `(loop while ,test do (progn ,@body)))

(cl:defun plist-get (plist prop)
  (getf plist prop))

(cl:defun plist-put (plist prop value)
  (let ((p plist))
    (setf (getf p prop) value)
    p))

(cl:defun setcdr (cell newcdr)
  "ELisp-ish SETCDR."
  (unless (consp cell)
    (error "ELISP:SETCDR expected cons, got: ~S" cell))
  (setf (cdr cell) newcdr)
  newcdr)

(cl:defun setcar (cell newcar)
  "ELisp-ish SETCAR."
  (unless (consp cell)
    (error "ELISP:SETCAR expected cons, got: ~S" cell))
  (setf (car cell) newcar)
  newcar)

(cl:defun car-safe (x)
  "ELisp-ish CAR-SAFE."
  (if (consp x) (car x) nil))

(cl:defun cdr-safe (x)
  "ELisp-ish CDR-SAFE."
  (if (consp x) (cdr x) nil))

(cl:defun assq (key alist)
  "ELisp-ish ASSQ."
  (dolist (cell alist nil)
    (when (and (consp cell) (eq (car cell) key))
      (return cell))))

(cl:defun rassq (value alist)
  "ELisp-ish RASSQ."
  (dolist (cell alist nil)
    (when (and (consp cell) (eq (cdr cell) value))
      (return cell))))

(cl:defun memq (elt list)
  "ELisp-ish MEMQ."
  (loop for tail on list
        when (eq elt (car tail)) do (return tail)
        finally (return nil)))

(cl:defun delq (elt list)
  "ELisp-ish DELQ (destructive eq-based deletion)."
  (labels ((skip-head (xs)
             (loop while (and (consp xs) (eq elt (car xs))) do
               (setf xs (cdr xs)))
             xs))
    (let* ((head (skip-head list))
           (prev head)
           (cur (and (consp head) (cdr head))))
      (loop while (consp cur) do
        (cond
         ((eq elt (car cur))
          (setf (cdr prev) (cdr cur))
          (setf cur (cdr cur)))
         (t
          (setf prev cur)
          (setf cur (cdr cur)))))
      head)))

(cl:defun proper-list-p (x)
  "Bring-up subset of ELisp `proper-list-p'.

Returns the length of X if it is a proper list, otherwise nil."
  (cond
   ((null x) 0)
   ((not (consp x)) nil)
   (t
    (let ((slow x)
          (fast x)
          (len 0))
      (loop
        ;; Step FAST once.
        (cond
         ((null fast) (return len))
         ((not (consp fast)) (return nil))
         (t
          (incf len)
          (setf fast (cdr fast))))
        ;; Cycle check.
        (when (eq fast slow) (return nil))
        ;; Step FAST again; step SLOW once.
        (cond
         ((null fast) (return len))
         ((not (consp fast)) (return nil))
         (t
          (incf len)
          (setf fast (cdr fast))
          (setf slow (cdr slow))))
        (when (eq fast slow) (return nil)))))))

(cl:defun recordp (_x)
  "Bring-up stub for ELisp `recordp'."
  (declare (cl:ignore _x))
  nil)

(eval-when (:load-toplevel :execute)
  ;; Upstream expects `string=' to be an alias for `string-equal' (used by ERT).
  (defalias 'string= 'string-equal))
