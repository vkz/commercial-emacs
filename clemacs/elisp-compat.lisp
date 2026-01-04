(in-package #:elisp)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (cl:require "SB-CLTL2"))

(cl:defun symbol-name (sym)
  "ELisp-ish SYMBOL-NAME that returns lowercase names by default."
  (string-downcase (cl:symbol-name sym)))

(cl:defun intern (name &optional (package *package*))
  "ELisp-ish INTERN; canonicalizes strings to CL-style names.

This is a pragmatic compatibility shim, not a full obarray model."
  (etypecase name
    (string
     (cl:intern (string-upcase name) package))
    (symbol name)))

(cl:defmacro function (arg)
  "ELisp-ish FUNCTION.

Emacs Lisp's `function' special form is more of a \"function designator\"
than a strict CL:FUNCTION: for symbols, it yields the symbol (resolved later
by `funcall' / `apply').  For lambdas, we keep the form as data so early
bootstrap loads don't macroexpand/compile lambda bodies."
  (cond
   ((symbolp arg)
    `(quote ,arg))
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
  (declare (ignore lexical))
  (cl:eval (%elisp-rewrite form)))

(cl:defun sxhash-equal (object)
  "Compatibility shim for the C primitive `sxhash-equal'."
  (cl:sxhash object))

(cl:defun % (x y)
  "Bring-up subset of ELisp `%'."
  (unless (and (integerp x) (integerp y))
    (error "ELISP:% expects integers, got: ~S ~S" x y))
  (cl:rem x y))

(cl:defun aref (array idx)
  "ELisp-ish AREF.

For strings, return a character code integer (Emacs Lisp semantics)."
  (let ((v (cl:aref array idx)))
    (if (stringp array) (char-code v) v)))

(cl:defsetf aref (array idx) (value)
  (let ((a (gensym "ARRAY"))
        (i (gensym "IDX"))
        (v (gensym "VALUE")))
    `(let ((,a ,array)
           (,i ,idx)
           (,v ,value))
       (setf (cl:aref ,a ,i)
             (if (stringp ,a)
                 (if (integerp ,v) (code-char ,v) ,v)
                 ,v)))))

(cl:defun char-to-string (ch)
  "Bring-up subset of ELisp `char-to-string'."
  (cond
   ((integerp ch) (string (code-char ch)))
   ((characterp ch) (string ch))
   (t (error "ELISP:CHAR-TO-STRING expects character code, got: ~S" ch))))

(cl:defun concat (&rest parts)
  "Stub for ELisp `concat'."
  (with-output-to-string (out)
    (dolist (p parts)
      (typecase p
        (null nil)
        (string (write-string p out))
        (character (write-char p out))
        (t (write-string (princ-to-string p) out))))))

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
        (loop for ch across s do (push ch out)))
       ((consp s)
        (dolist (x s) (push x out)))
       (t
        (error "ELISP:VCONCAT unsupported sequence: ~S" (type-of s)))))
    (coerce (nreverse out) 'vector)))

(cl:defun downcase (s)
  "Bring-up subset of ELisp `downcase'."
  (unless (stringp s)
    (error "ELISP:DOWNCASE expects a string, got: ~S" s))
  (string-downcase s))

(cl:defun multibyte-string-p (s)
  "Bring-up subset of the C primitive `multibyte-string-p'."
  (and (stringp s) t))

(cl:defun upcase (s)
  "Bring-up subset of ELisp `upcase'."
  (unless (stringp s)
    (error "ELISP:UPCASE expects a string, got: ~S" s))
  (string-upcase s))

(cl:defun string= (a b)
  "ELisp-ish STRING=.

Unlike CL:STRING-EQUAL, Emacs's `string-equal' is case-sensitive (an alias of
`string=')."
  (let ((a (if (symbolp a) (symbol-name a) a))
        (b (if (symbolp b) (symbol-name b) b)))
    (unless (and (stringp a) (stringp b))
      (error "ELISP:STRING= expects strings or symbols, got: ~S ~S" a b))
    (cl:string= a b)))

(cl:defun string-equal (a b)
  "ELisp-ish STRING-EQUAL (case-sensitive; alias of `string=')."
  (string= a b))

(cl:defun capitalize (s)
  "Bring-up subset of ELisp `capitalize'."
  (unless (stringp s)
    (error "ELISP:CAPITALIZE expects a string, got: ~S" s))
  (string-capitalize s))

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

(cl:defun match-data ()
  "Bring-up subset of ELisp `match-data'."
  (and *match-data* (copy-list *match-data*)))

(cl:defun set-match-data (data &optional _reseat _inhibit-read-only)
  "Bring-up subset of ELisp `set-match-data'."
  (declare (ignore _reseat _inhibit-read-only))
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
  (let* ((s (or string *match-source-string*))
         (start (match-beginning n))
         (end (match-end n)))
    (and s start end (subseq s start end))))

(cl:defun %elisp-regexp->pcre (regexp)
  "Translate a (very) small subset of Emacs regexps to PCRE.

Key rule: Emacs uses backslash escapes for grouping/alternation
(`\\(...\\)' and `\\|'), while unescaped parens and | are literals.
PCRE uses unescaped parens/| as metacharacters.

So we:
- convert escaped Emacs grouping/alternation to PCRE metacharacters,
- escape otherwise-unescaped PCRE metacharacters to preserve literal meaning,
- translate `\\` and `\\'' anchors to ^/$."
  (with-output-to-string (out)
    (loop with i = 0
          with n = (length regexp)
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
                    (#\` (write-char #\^ out))
                    (#\' (write-char #\$ out))
                    (otherwise
                     (write-char #\\ out)
                     (write-char next out)))))
               ((find ch "()|{}" :test #'char=)
                (write-char #\\ out)
                (write-char ch out))
               (t
                (write-char ch out))))
            (incf i))))

(cl:defun %string-match-scanner (regexp case-fold-search)
  (let* ((key (list regexp (and case-fold-search t)))
         (cached (gethash key *string-match-scanner-cache*)))
    (or cached
        (setf (gethash key *string-match-scanner-cache*)
              (cl-ppcre:create-scanner (%elisp-regexp->pcre regexp)
                                       :case-insensitive-mode
                                       (and case-fold-search t))))))

(cl:defun string-match (regexp string &optional start _inhibit-modify)
  "Bring-up `string-match' using cl-ppcre as a temporary regexp engine."
  (declare (ignore _inhibit-modify))
  (unless (and (stringp regexp) (stringp string))
    (error "ELISP:STRING-MATCH expects strings, got: %S %S" regexp string))
  (let ((start (or start 0)))
    (unless (and (integerp start) (<= 0 start))
      (error "ELISP:STRING-MATCH bad start: %S" start))
    (multiple-value-bind (mstart mend reg-starts reg-ends)
        (cl-ppcre:scan (%string-match-scanner regexp case-fold-search)
                       string
                       :start start)
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

(cl:defun prin1-to-string (object &optional _noescape)
  "Bring-up subset of ELisp `prin1-to-string'.

This is only intended to be readable by our ELisp `read-from-string'."
  (declare (ignore _noescape))
  (cond
   ;; Emacs expects hash-tables to be printable/readable when the feature is
   ;; available. For bring-up, keep it simple: print an empty hash-table in a
   ;; read-time-eval form so `read-from-string' can reconstruct one.
   ((cl:hash-table-p object) "#.(make-hash-table)")
   (t (cl:prin1-to-string object))))

(cl:defun read-from-string (string &optional start end)
  "Bring-up subset of ELisp `read-from-string'.

Return (OBJECT . POSITION) where POSITION is the index of the first unread
character in STRING."
  (unless (stringp string)
    (error "ELISP:READ-FROM-STRING expects a string, got: %S" string))
  (let* ((start (or start 0))
         (end (or end (length string))))
    (unless (and (integerp start) (<= 0 start))
      (error "ELISP:READ-FROM-STRING bad start: %S" start))
    (unless (and (integerp end) (<= start end) (<= end (length string)))
      (error "ELISP:READ-FROM-STRING bad end: %S" end))
    (let ((*package* (find-package "ELISP"))
          (*readtable* (elisp::%ensure-elisp-readtable))
          (*read-eval* t))
      (multiple-value-bind (obj pos)
          (cl:read-from-string string nil :eof :start start :end end)
        (when (eq obj :eof)
          (error "ELISP:READ-FROM-STRING EOF"))
        (cons obj pos)))))

(cl:defun string-to-number (string)
  "Bring-up subset of ELisp `string-to-number'."
  (unless (stringp string)
    (error "ELISP:STRING-TO-NUMBER expects string, got: ~S" string))
  (handler-case
      (parse-integer string :junk-allowed t)
    (cl:error () 0)))

(cl:defun copy-sequence (sequence)
  "ELisp-ish COPY-SEQUENCE."
  (typecase sequence
    (null nil)
    (cons (copy-list sequence))
    (string (copy-seq sequence))
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
         (out nil))
    (loop for (k v) on args by (cl:function cl:cddr) do
      (cond
       ((eq k :test)
        (setf out (list* mapped-test :test out)))
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
            (setf out (list* wk :weakness out)))))
       ((or (eq k :size) (eq k :rehash-size) (eq k :rehash-threshold))
        (setf out (list* v k out)))
       (t
        nil)))
    (apply #'cl:make-hash-table (nreverse out))))

(defparameter features nil)

(cl:defun featurep (feature)
  "Stub for ELisp `featurep'."
  (and (member feature features :test 'eq) t))

(cl:defun provide (feature &optional _subfeatures)
  "Stub for ELisp `provide'."
  (declare (ignore _subfeatures))
  (pushnew feature features :test 'eq)
  feature)

(cl:defun require (feature &optional _filename _noerror)
  "Stub for ELisp `require'.

Currently does not load code; it only records FEATURE as provided."
  (declare (ignore _filename _noerror))
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
              ((stringp x) (coerce x 'list))
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
                       (declare (ignore _vars))
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
  (declare (ignore _parents _docstring _args))
  `(progn ',name))

(cl:defmacro defcustom (symbol value _docstring &rest _args)
  "Stub for ELisp `defcustom'."
  (declare (ignore _docstring _args))
  `(defparameter ,symbol ,value))

(cl:defmacro defface (face _spec _docstring &rest _args)
  "Stub for ELisp `defface'."
  (declare (ignore _spec _docstring _args))
  `(progn ',face))

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
          "Arithmetic singularity error")))

(cl:defmacro cl-assert (form &rest _args)
  "Bring-up subset of cl-lib's `cl-assert'.

Upstream ELisp often passes extra arguments (e.g. SHOW-ARGS, message
formatting). We currently ignore them and delegate to CL:ASSERT on FORM."
  (declare (ignore _args))
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
           (walk (xs)
             (cond
              ((null xs) nil)
              ((eq (car xs) 'by)
               (cons 'by (cons (rewrite-by (cadr xs)) (walk (cddr xs)))))
              (t (cons (car xs) (walk (cdr xs)))))))
    `(cl:loop ,@(walk clauses))))

(cl:defmacro cl-etypecase (keyform &rest clauses)
  "Bring-up subset of cl-lib's `cl-etypecase'."
  `(cl:etypecase ,keyform ,@clauses))

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
  (declare (ignore _x))
  nil)

(cl:defun cl-intersection (list1 list2 &rest args &key (test 'eql) key &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-intersection'."
  (declare (ignore args))
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
  (declare (ignore args))
  (let ((test-fn
          (cond
           ((or (eq test 'eq) (eq test 'cl:eq)) #'cl:eq)
           ((or (eq test 'eql) (eq test 'cl:eql)) #'cl:eql)
           ((or (eq test 'equal) (eq test 'cl:equal)) #'cl:equalp)
           ((or (eq test 'equalp) (eq test 'cl:equalp)) #'cl:equalp)
           ((functionp test) test)
           (t (cl:error "ELISP:CL-SET-DIFFERENCE unsupported :test: ~S" test)))))
    (cl:set-difference list1 list2 :test test-fn :key key)))

(cl:defun cl-position (item sequence &rest args)
  "Bring-up subset of cl-lib's `cl-position'."
  (let* ((item (if (and (integerp item) (stringp sequence))
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
    (gensym (string-upcase p))))

(cl:defun cl-coerce (object type)
  "Bring-up subset of cl-lib's `cl-coerce'.

ELisp tends to pass type names as ELISP package symbols (e.g. `list'),
whereas CL:COERCE expects CL type names."
  (let ((type (if (symbolp type)
                  (intern (string-upcase (symbol-name type)) (find-package "CL"))
                  type)))
    (coerce object type)))

(cl:defun cl-search (sequence1 sequence2 &rest args &key (test 'eql) &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-search'."
  (declare (ignore args))
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
  (declare (ignore args))
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

(cl:defun cl--find-class (name)
  "Bring-up stub for cl-lib's internal `cl--find-class'."
  (and (symbolp name) (get name 'cl--class)))

(cl:defsetf cl--find-class (name) (value)
  `(progn
     (put ,name 'cl--class ,value)
     ,value))

(cl:defmacro cl-defstruct (&rest args)
  "Minimal subset of cl-lib's `cl-defstruct'.

cl-lib's `cl-defstruct' provides a constructor function with the same name as
the struct (e.g. `ert-test-passed'), whereas CL:DEFSTRUCT defaults to
`make-<name>'.  Upstream ERT depends on the cl-lib behavior."
  (let* ((spec (car args))
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
         (args* (cons spec* (cdr args))))
    (cond
     ((or (not (symbolp name))
          (eq (symbol-package name) (find-package "CL"))
          ctor-nil-p)
      `(cl:defstruct ,@args*))
     (t
      (let* ((make-name
               (intern (cl:format nil "MAKE-~A" (string-upcase (symbol-name name)))
                       (symbol-package name)))
             (ctor (or (car ctors) make-name)))
        `(progn
           (cl:defstruct ,@args*)
           (defun ,name (&rest initargs)
             (if (and initargs
                      (keywordp (car initargs))
                      (cl:evenp (length initargs)))
                 (apply #',ctor initargs)
                 (funcall #',ctor)))))))))

(cl:defmacro cl-defgeneric (name args &rest rest)
  "Bring-up subset of cl-generic's `cl-defgeneric'.

Defines a CLOS generic function, and (when BODY is provided) a default method."
  (unless (and (symbolp name) (listp args))
    (cl:error "ELISP:CL-DEFGENERIC expects (NAME ARGS ...), got: ~S ~S" name args))
  (let* ((doc (and rest (stringp (car rest)) (pop rest)))
         (body rest)
         (method-args
           (loop for a in args
                 while (and (symbolp a) (not (keywordp a)) (not (char= (char (symbol-name a) 0) #\&)))
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
  (let ((method-args
          (mapcar
           (lambda (a)
             (cond
              ((symbolp a) a)
              ((and (consp a) (= (length a) 2) (symbolp (car a)))
               a)
              (t (cl:error "ELISP:CL-DEFMETHOD unsupported arg spec: ~S" a))))
           args)))
    `(cl:defmethod ,name ,method-args
       ,@body)))

(cl:defun put (symbol prop value)
  "ELisp-ish PUT for symbol plists."
  (setf (get symbol prop) value)
  value)

(cl:defun getenv (var)
  "Bring-up subset of ELisp `getenv'."
  (unless (stringp var)
    (error "ELISP:GETENV expects a string, got: ~S" var))
  (let ((v (uiop:getenv var)))
    (and v (stringp v) v)))

(cl:defvar user-emacs-directory
  (namestring (merge-pathnames ".emacs.d/" (user-homedir-pathname))))

(cl:defun locate-user-emacs-file (new-name &optional _old-name)
  "Bring-up subset of ELisp `locate-user-emacs-file'."
  (declare (ignore _old-name))
  (unless (stringp new-name)
    (error "ELISP:LOCATE-USER-EMACS-FILE expects string, got: ~S" new-name))
  (namestring (merge-pathnames new-name user-emacs-directory)))

(cl:defun make-list (length init)
  "ELisp-ish MAKE-LIST."
  (unless (and (integerp length) (>= length 0))
    (error "ELISP:MAKE-LIST expects nonnegative integer length, got: ~S" length))
  (cl:make-list length :initial-element init))

(defvar *charset-aliases* (cl:make-hash-table :test 'eq))

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
  (declare (ignore _docstring))
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
(defparameter noninteractive t)
(defparameter current-load-list nil)
(cl:defvar load-history nil)
(cl:defvar after-load-alist nil)
(cl:defvar describe-symbol-backends nil)
(cl:defvar minor-mode-alist nil)
(cl:defvar help-char 8)

;; ---------------------------------------------------------------------------
;; Minimal buffer/marker surface (enough for upstream ERT bring-up)
;; ---------------------------------------------------------------------------

(defstruct elisp-buffer
  (name "" :type string)
  (text "" :type string)
  (point 1 :type integer))

(defstruct elisp-marker
  (buffer nil)
  (position nil))

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
  (elisp-marker-position marker))

(defvar *buffer-table* (cl:make-hash-table :test 'cl:equal))

(cl:defun %register-buffer (buf)
  (setf (gethash (elisp-buffer-name buf) *buffer-table*) buf)
  buf)

(defvar *messages-buffer* (%register-buffer (make-elisp-buffer :name "*Messages*")))
(defvar *current-buffer* *messages-buffer*)
(defparameter message-log-max t)

(cl:defun current-buffer ()
  *current-buffer*)

(cl:defun messages-buffer ()
  *messages-buffer*)

(cl:defun get-buffer (buffer-or-name)
  "Bring-up subset of ELisp `get-buffer'."
  (etypecase buffer-or-name
    (elisp-buffer buffer-or-name)
    (string (gethash buffer-or-name *buffer-table*))
    (null nil)))

(cl:defun get-buffer-create (name &optional _inhibit-buffer-hooks)
  "Bring-up subset of ELisp `get-buffer-create'."
  (declare (ignore _inhibit-buffer-hooks))
  (unless (stringp name)
    (error "ELISP:GET-BUFFER-CREATE expects a string name, got: ~S" name))
  (or (gethash name *buffer-table*)
      (%register-buffer (make-elisp-buffer :name name))))

(cl:defun generate-new-buffer-name (name &optional _ignore)
  "Bring-up subset of ELisp `generate-new-buffer-name'."
  (declare (ignore _ignore))
  (unless (stringp name)
    (error "ELISP:GENERATE-NEW-BUFFER-NAME expects a string, got: ~S" name))
  (if (null (gethash name *buffer-table*))
      name
      (loop for n from 2 do
        (let ((cand (cl:format nil "~A<~D>" name n)))
          (when (null (gethash cand *buffer-table*))
            (return cand))))))

(cl:defun kill-buffer (buffer-or-name)
  "Bring-up subset of ELisp `kill-buffer'."
  (let ((buf (get-buffer buffer-or-name)))
    (unless buf
      (return-from kill-buffer nil))
    (remhash (elisp-buffer-name buf) *buffer-table*)
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
  `(progn ,@body))

(cl:defun point ()
  (elisp-buffer-point *current-buffer*))

(cl:defun point-min ()
  1)

(cl:defun point-max ()
  (1+ (length (elisp-buffer-text *current-buffer*))))

(cl:defun goto-char (pos)
  (unless (and (integerp pos) (<= (point-min) pos) (<= pos (point-max)))
    (error "ELISP:GOTO-CHAR out of range: ~S" pos))
  (setf (elisp-buffer-point *current-buffer*) pos)
  pos)

(cl:defun point-max-marker ()
  (make-elisp-marker :buffer *current-buffer* :position (point-max)))

(cl:defun set-marker (marker position &optional buffer)
  (unless (elisp-marker-p marker)
    (error "ELISP:SET-MARKER expected marker, got: ~S" marker))
  (cond
   ((null position)
    (setf (elisp-marker-buffer marker) nil
          (elisp-marker-position marker) nil))
   (t
    (unless (and (integerp position) (plusp position))
      (error "ELISP:SET-MARKER bad position: ~S" position))
    (setf (elisp-marker-buffer marker) (or buffer *current-buffer*)
          (elisp-marker-position marker) position)))
  marker)

(cl:defun %pos (x)
  (etypecase x
    (integer x)
    (elisp-marker (or (elisp-marker-position x) (error "Marker has no position")))))

(cl:defun buffer-substring (start end)
  (let* ((s (%pos start))
         (e (%pos end))
         (txt (elisp-buffer-text *current-buffer*)))
    (when (> s e)
      (error "ELISP:BUFFER-SUBSTRING start > end: ~S ~S" start end))
    (subseq txt (1- s) (1- e))))

(cl:defun delete-region (start end)
  (let* ((s (%pos start))
         (e (%pos end))
         (txt (elisp-buffer-text *current-buffer*)))
    (when (> s e)
      (error "ELISP:DELETE-REGION start > end: ~S ~S" start end))
    (setf (elisp-buffer-text *current-buffer*)
          (concatenate 'string (subseq txt 0 (1- s)) (subseq txt (1- e))))
    (when (> (point) (point-max))
      (goto-char (point-max)))
    nil))

(cl:defun insert (&rest parts)
  (let* ((s (with-output-to-string (out)
              (dolist (p parts)
                (typecase p
                  (null nil)
                  (string (write-string p out))
                  (character (write-char p out))
                  (t (write-string (princ-to-string p) out))))))
         (txt (elisp-buffer-text *current-buffer*))
         (idx (1- (point))))
    (setf (elisp-buffer-text *current-buffer*)
          (concatenate 'string (subseq txt 0 idx) s (subseq txt idx)))
    (goto-char (+ (point) (length s)))
    nil))

(cl:defun buffer-string ()
  "Bring-up subset of ELisp `buffer-string'."
  (elisp-buffer-text *current-buffer*))

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

(cl:defun backtrace-get-frames (_debugfun)
  "Bring-up stub for `backtrace-get-frames'.

ERT uses this to capture a backtrace; we currently record none."
  (declare (ignore _debugfun))
  (list nil))

(cl:defun macroexp-file-name ()
  "Stub for ELisp `macroexp-file-name'."
  nil)

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
          (declare (ignore name))
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
    `(let ((,v ,expr))
       (block ,done
         ,@(mapcar
            (lambda (clause)
              (destructuring-bind (pattern &rest body) clause
                (cond
                 ((eq pattern '_)
                  `(return-from ,done (progn ,@body)))
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
                  (let ((tmp (gensym "PCASE-TMP-")))
                    (multiple-value-bind (ll checks _vars)
                        (%pcase--template->lambda-list (cadr pattern))
                      (declare (ignore _vars))
                      `(let ((,tmp ,v))
                         (handler-case
                             (destructuring-bind ,ll ,tmp
                               (when (and ,@checks)
                                 (return-from ,done (progn ,@body))))
                           (cl:error () nil))))))
                 ((null pattern)
                  `(when (null ,v)
                     (return-from ,done (progn ,@body))))
                 (t
                  (cl:error "ELISP:PCASE-EXHAUSTIVE unsupported pattern: ~S" pattern)))))
            clauses)
         (error "pcase-exhaustive: no match for %S" ,v)))))

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
  ;; Do not recurse into subforms yet: SBCL macroexpansions can include
  ;; internal/circular structures, and ERT bring-up only requires expanding
  ;; the top-level macro call (e.g. (foo) => (progn ...)).
  (let ((cur form)
        (expandedp t)
        (guard 0))
    (loop while expandedp do
      (incf guard)
      (when (> guard 200)
        (cl:error "ELISP:MACROEXPAND-ALL appears to loop on: ~S" cur))
      (let ((prev cur))
        (multiple-value-setq (cur expandedp)
          (%macroexpand-all--macroexpand-1 cur env))
        (when (and expandedp (eq cur prev))
          (setf expandedp nil))))
    cur))

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
                           (throw ',tag (list :err (cons 'error (list ,e))))))))
                  (list :ok ,bodyform)))))
         (cond
          ((and (consp ,out) (eq (car ,out) :ok))
           (let ((res (cadr ,out)))
             ,(if success-clause
                  (destructuring-bind (_ &rest body) success-clause
                    (declare (ignore _))
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
    (cl:error "ELISP:ERROR expects a string format, got: ~S" fmt))
  (let ((i 0)
        (n (length fmt))
        (rest args))
    (with-output-to-string (out)
      (loop while (< i n) do
        (let ((ch (char fmt i)))
          (if (char= ch #\%)
              (progn
                (incf i)
                (when (>= i n)
                  (write-char #\% out)
                  (return))
                (let* ((code (char fmt i))
                       (arg-present (consp rest))
                       (arg (if arg-present (pop rest) nil)))
                  (case code
                    (#\% (write-char #\% out))
                    (#\s (when arg-present
                           (write-string (cl:princ-to-string arg) out)))
                    (#\S (when arg-present
                           (write-string (cl:prin1-to-string arg) out)))
                    (#\d (when arg-present
                           (write-string (cl:princ-to-string arg) out)))
                    (#\x (when arg-present
                           (write-string
                            (cl:format nil "~x"
                                       (cond
                                        ((integerp arg) arg)
                                        ((cl:characterp arg) (char-code arg))
                                        (t arg)))
                            out)))
                    (#\c (when arg-present
                           (write-char (cond
                                        ((cl:characterp arg) arg)
                                        ((integerp arg) (or (code-char arg) #\?))
                                        (t (char (cl:princ-to-string arg) 0)))
                                      out)))
                    (otherwise
                     (write-char #\% out)
                     (write-char code out)))))
              (write-char ch out)))
        (incf i)))))

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
  (typecase key
    (string key)
    (vector (write-to-string key :escape t))
    (character (string key))
    (integer (cl:format nil "#<keycode ~D>" key))
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
  (declare (ignore _noangles))
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

(cl:defmacro define-derived-mode (child _parent _name &optional docstring &rest _body)
  "Bring-up subset of ELisp `define-derived-mode'.

For now we:
- create CHILD-hook and CHILD-map variables (if not already bound),
- define a no-op mode function CHILD.

This is sufficient for many shipped Elisp files to load; it is not a full
major-mode implementation."
  (declare (ignore _parent _name _body))
  (let ((hook (%mode-hook-symbol child))
        (map (%mode-map-symbol child)))
    `(progn
       (cl:defvar ,hook nil)
       (cl:defvar ,map (make-elisp-keymap))
       (defun ,child (&rest _args)
         ,@(when (stringp docstring) (list docstring))
         (declare (ignore _args))
         nil)
       ',child)))

(cl:defmacro easy-menu-define (symbol _keymap _doc menu)
  "Bring-up stub for ELisp `easy-menu-define'."
  (declare (ignore _keymap _doc))
  `(progn
     (cl:defvar ,symbol ,menu)
     ',symbol))

(cl:defun define-button-type (&rest _args)
  "Bring-up stub for ELisp `define-button-type'."
  (declare (ignore _args))
  nil)

(cl:defun add-hook (hook function &optional append _local)
  "Bring-up subset of ELisp `add-hook'.

HOOK is a symbol naming a hook variable whose value is a list of functions."
  (declare (ignore _local))
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
  (declare (ignore _local))
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
  (declare (ignore _compare-fn))
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
  (declare (ignore _name))
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
  (declare (ignore _args))
  nil)

(cl:defmacro defconst (name value &optional docstring)
  "ELisp-ish DEFCONST (currently just DEFPARAMETER).

If NAME lives in the CL package, ignore the definition."
  (declare (ignore docstring))
  (if (and (symbolp name) (eq (symbol-package name) (find-package "CL")))
      `(progn ',name)
      `(defparameter ,name ,value)))

(defparameter -c-@ 0)

(cl:defmacro with-suppressed-warnings (_spec &body body)
  "Compatibility shim; ignores suppression spec."
  (declare (ignore _spec))
  `(progn ,@body))

(cl:defun set-advertised-calling-convention (&rest _args)
  "Stub for ELisp `set-advertised-calling-convention'."
  (declare (ignore _args))
  nil)

(cl:defun make-obsolete-variable (&rest _args)
  "Stub for ELisp `make-obsolete-variable'."
  (declare (ignore _args))
  nil)

(cl:defmacro defmacro (name lambda-list &body body)
  "Define a macro without mutating CL package symbols.

If NAME lives in the CL package, ignore the definition (this avoids
trying to redefine CL special operators and other locked symbols while
loading upstream ELisp)."
  (if (and (symbolp name) (eq (symbol-package name) (find-package "CL")))
      `(progn ',name)
      `(cl:defmacro ,name ,lambda-list ,@body)))

(cl:defmacro defun (name lambda-list &body body)
  "Define a function without mutating CL package symbols.

If NAME lives in the CL package, ignore the definition (this avoids
trying to redefine locked symbols while loading upstream ELisp)."
  (if (and (symbolp name) (eq (symbol-package name) (find-package "CL")))
      `(progn ',name)
      `(cl:defun ,name ,lambda-list ,@body)))

(cl:defmacro defsubst (name lambda-list &body body)
  "ELisp-ish DEFSUBST (currently just DEFUN)."
  `(defun ,name ,lambda-list ,@body))

(cl:defun equal (a b)
  (cond
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

(cl:defun equal-including-properties (a b)
  "Bring-up stub for ELisp `equal-including-properties'.

clemacs does not yet model text properties, so this currently behaves like
`equal'."
  (equal a b))

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
   (t (cl:type-of object))))

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
  (declare (ignore _docstring))
  (setf (gethash new-alias *elisp-variable-aliases*) base-variable)
  new-alias)

(cl:defun define-obsolete-variable-alias (obsolete-name current-name &optional _since)
  "Stub for ELisp `define-obsolete-variable-alias'."
  (declare (ignore _since))
  (defvaralias obsolete-name current-name)
  obsolete-name)

(cl:defun define-obsolete-function-alias (obsolete-name current-definition &optional _since _docstring)
  "Stub for ELisp `define-obsolete-function-alias'."
  (declare (ignore _since _docstring))
  (defalias obsolete-name current-definition)
  obsolete-name)

(cl:defun autoload (function file &optional _docstring _interactive _type)
  "Stub for ELisp `autoload'.

Stores a non-callable marker in the function cell; calling it will
fail until proper autoload support exists."
  (declare (ignore _docstring _interactive _type))
  (unless (symbolp function)
    (error "ELISP:AUTOLOAD expects a function symbol, got: ~S" function))
  (fset function (list 'autoload file))
  function)

(cl:defun symbol-file (_symbol &optional _type)
  "Bring-up stub for ELisp `symbol-file'."
  (declare (ignore _symbol _type))
  nil)

(cl:defmacro with-demoted-errors (_format &rest body)
  "Bring-up subset of ELisp `with-demoted-errors'.

Evaluate BODY, but if an error is signaled, demote it and return nil."
  (declare (ignore _format))
  (let ((err (gensym "ERR")))
    `(condition-case ,err
         (progn ,@body)
       (error nil))))

(cl:defun make-variable-buffer-local (variable)
  "Stub for ELisp `make-variable-buffer-local'."
  variable)

(cl:defun default-boundp (symbol)
  "Stub for ELisp `default-boundp'.

Currently treats \"default\" binding as CL's global binding model (no
buffer-local values yet)."
  (cl:boundp (%resolve-variable-alias symbol)))

(cl:defun local-variable-if-set-p (_symbol &optional _buffer)
  "Stub for ELisp `local-variable-if-set-p'."
  (declare (ignore _symbol _buffer))
  nil)

(cl:defun default-value (symbol)
  "Stub for ELisp `default-value'."
  (symbol-value symbol))

(cl:defun set-default (symbol value)
  "Stub for ELisp `set-default'."
  (set symbol value))

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
  (declare (ignore _docstring))
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
  (declare (ignore _x))
  nil)

(eval-when (:load-toplevel :execute)
  ;; Upstream expects `string=' to be an alias for `string-equal' (used by ERT).
  (defalias 'string= 'string-equal))
