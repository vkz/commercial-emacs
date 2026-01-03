(in-package #:elisp)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "SB-CLTL2"))

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

This differs from CL:FUNCTION by allowing symbol references to be resolved
at call time (via ELISP:FUNCALL), which makes bootstrapping and forward
references less strict than CL."
  (cond
   ((symbolp arg)
    `(quote ,arg))
   ((and (consp arg) (eq (car arg) 'lambda))
    `(cl:function ,arg))
   (t
   `(cl:function ,arg))))

(defvar *elisp-function-cells* (make-hash-table :test 'eq))

(cl:defun symbol-function (symbol)
  "ELisp-ish SYMBOL-FUNCTION.

Returns NIL if SYMBOL has no function cell value."
  (multiple-value-bind (value presentp)
      (gethash symbol *elisp-function-cells*)
    (cond
     (presentp value)
     ((cl:fboundp symbol) (cl:symbol-function symbol))
     (t nil))))

(cl:defun fboundp (symbol)
  "ELisp-ish FBOUNDP."
  (multiple-value-bind (value presentp)
      (gethash symbol *elisp-function-cells*)
    (if presentp
        (not (null value))
        (cl:fboundp symbol))))

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
                (error 'undefined-function :name cur))
              (setf cur next)))
           (t
            (error "ELISP: function cell is not callable: ~S" cur)))
        finally
          (error "ELISP: function indirection loop for ~S" fn)))

(cl:defun funcall (fn &rest args)
  "ELisp-ish FUNCALL that accepts symbols and lambda forms."
  (cl:apply (%resolve-function fn) args))

(cl:defun sxhash-equal (object)
  "Compatibility shim for the C primitive `sxhash-equal'."
  (cl:sxhash object))

(cl:defun put (symbol prop value)
  "ELisp-ish PUT for symbol plists."
  (setf (get symbol prop) value)
  value)

(defstruct elisp-keymap
  (table (make-hash-table :test 'cl:equal))
  (parent nil))

(cl:defun make-keymap ()
  "Extremely small stub for ELisp `make-keymap'."
  (make-elisp-keymap))

(cl:defun make-sparse-keymap (&optional _name)
  "Extremely small stub for ELisp `make-sparse-keymap'."
  (declare (ignore _name))
  (make-elisp-keymap))

(cl:defun define-key (keymap key definition)
  "Extremely small stub for ELisp `define-key'.

Only supports string KEYs, and stores DEFINITION verbatim."
  (unless (typep keymap 'elisp-keymap)
    (error "ELISP:DEFINE-KEY expected a keymap, got: ~S" keymap))
  (unless (stringp key)
    (error "ELISP:DEFINE-KEY only supports string keys for now, got: ~S" key))
  (setf (gethash key (elisp-keymap-table keymap)) definition)
  definition)

(cl:defun make-obsolete (&rest _args)
  "Stub for ELisp `make-obsolete'."
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
   ((and (vectorp a) (vectorp b))
    (and (= (length a) (length b))
         (loop for i from 0 below (length a)
               always (equal (aref a i) (aref b i)))))
   (t (cl:equal a b))))

(cl:defun %lexical-variable-p (symbol env)
  (multiple-value-bind (kind)
      (sb-cltl2:variable-information symbol env)
    (eq kind :lexical)))

(cl:defmacro setq (&environment env &rest pairs)
  (unless (evenp (length pairs))
    (error "ELISP:SETQ expects an even number of arguments"))

  (let ((forms nil))
    (loop for (var val) on pairs by #'cddr do
      (unless (symbolp var)
        (error "ELISP:SETQ only supports symbol variables, got: ~S" var))
      (push (if (%lexical-variable-p var env)
                `(cl:setq ,var ,val)
                `(setf (symbol-value ',var) ,val))
            forms))
    `(progn ,@(nreverse forms))))

(cl:defun fset (symbol definition)
  "Set SYMBOL's function cell to DEFINITION."
  (when (and (symbolp symbol)
             (eq (symbol-package symbol) (find-package "CL")))
    (return-from fset symbol))
  (setf (gethash symbol *elisp-function-cells*) definition)
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
