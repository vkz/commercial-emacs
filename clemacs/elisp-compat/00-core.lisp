(in-package #:elisp)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (cl:require "SB-CLTL2"))

;; `with-output-to-string' is also a CL macro; shadow it so ELisp code resolves
;; to our compatibility macro instead of tripping SBCL's package lock.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (shadow '(with-output-to-string macroexpand macroexpand-1)))

;; Upstream ELisp uses declaration specifiers that CL implementations don't know
;; about.  Declare them so SBCL doesn't spam style warnings during bring-up.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (declaim
   (declaration pure completion important-return-value
                side-effect-free error-free
                advertised-calling-convention obsolete)))

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
(cl:defvar overlay-arrow-variable-list nil)
(cl:defvar standard-display-table nil)
(cl:defvar buffer-display-table nil)
(cl:defvar window-system nil)
;; `disp-table.el` assumes this is a vector (it grows it on demand).
(cl:defvar glyph-table (make-array 32 :initial-element nil))
(cl:defvar text-property-default-nonsticky nil)
(cl:defvar comment-start-skip nil)
;; `ert-with-temp-file' (and friends) consult these during macroexpansion.
(cl:defvar coding-system-for-write nil)
(cl:defvar standard-output t)
;; Common command/key processing vars referenced early by upstream lisp/.
;; Bind to NIL for bring-up so loads don't spam UNBOUND warnings.
(cl:defvar current-prefix-arg nil)
(cl:defvar defining-kbd-macro nil)
(cl:defvar last-command-event nil)
(cl:defvar unread-command-events nil)
(cl:defvar executing-kbd-macro nil)
(cl:defvar keyboard-translate-table nil)
(cl:defvar help-form nil)
(cl:defvar line-spacing nil)
(cl:defvar xterm-mouse-mode nil)
(cl:defvar minibuffer-default-prompt-format nil)
(cl:defvar history-delete-duplicates nil)
(cl:defvar history-length nil)
(cl:defvar syntax-propertize-function nil)
(cl:defvar major-mode nil)
(cl:defvar auto-mode-alist nil)
(cl:defvar magic-fallback-mode-alist nil)
(cl:defvar minor-mode-map-alist nil)
(cl:defvar mode-line-mode-menu nil)
(cl:defvar load-path nil)
(cl:defvar load-file-rep-suffixes nil)
(cl:defvar temporary-file-directory nil)

(cl:defmacro bound-and-true-p (var)
  "Bring-up subset of ELisp `bound-and-true-p'."
  `(and (cl:boundp ',var) ,var))

(cl:defmacro interactive (&rest _spec)
  "Bring-up stub for ELisp `interactive'.

For now, clemacs runs all ELisp non-interactively, so this expands to NIL
without evaluating the interactive spec."
  (declare (cl:ignore _spec))
  nil)

(cl:defun ding (&optional _arg)
  "Bring-up stub for ELisp `ding'."
  (declare (cl:ignore _arg))
  nil)

(cl:defmacro defvar (var &optional (init nil init-supplied-p) doc)
  "ELisp-ish DEFVAR.

Accepts unibyte/multibyte docstrings and coerces them to a CL string so SBCL
recognizes them as docstrings (keeping subsequent DECLARE forms legal)."
  (let ((doc* (and doc
                   (if (cl:stringp doc) doc (%elisp-string->cl-string doc)))))
    (cond
     ((and (not init-supplied-p) (null doc*))
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
  (cl:shadow 'string-lessp (find-package "ELISP"))
  ;; These exist in CL too; shadow them so we can provide ELisp semantics
  ;; without tripping SBCL package locks.
  (cl:shadow 'assoc (find-package "ELISP"))
  (cl:shadow 'rassoc (find-package "ELISP")))

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
by `funcall' / `apply').  For lambdas, return a real CL function object so
upstream macroexpanders can safely parse lambda lists/bodies."
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
    ;; In ELisp, (function (lambda ...)) evaluates to a closure.
    ;; Keep this as a real CL function object so upstream `macroexpand` users
    ;; (notably `cl-generic`) see `#'(lambda ...)` rather than a quoted lambda
    ;; list and can safely parse the lambda list/body.
    `(cl:function ,arg))
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
        (when (cl:member next seen :test #'eq)
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
