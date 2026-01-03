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

(defvar *elisp-function-cells* (cl:make-hash-table :test 'eq))

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

(cl:defun concat (&rest parts)
  "Stub for ELisp `concat'."
  (with-output-to-string (out)
    (dolist (p parts)
      (typecase p
        (null nil)
        (string (write-string p out))
        (character (write-char p out))
        (t (write-string (princ-to-string p) out))))))

(cl:defun make-hash-table (&rest args &key (test 'eql) &allow-other-keys)
  "ELisp-ish MAKE-HASH-TABLE.

Emacs Lisp accepts `:test' values like 'eq/'eql/'equal/'equalp. We map
`equal' to CL:EQUALP to get vector element semantics, which is a closer
match to Elisp than CL:EQUAL."
  (unless (symbolp test)
    (error "ELISP:MAKE-HASH-TABLE only supports symbolic :test, got: ~S" test))
  (let* ((mapped-test
           (cond
            ((or (eq test 'eq) (eq test 'cl:eq)) 'cl:eq)
            ((or (eq test 'eql) (eq test 'cl:eql)) 'cl:eql)
            ((or (eq test 'equal) (eq test 'cl:equal)) 'cl:equalp)
            ((or (eq test 'equalp) (eq test 'cl:equalp)) 'cl:equalp)
            (t (error "ELISP:MAKE-HASH-TABLE unsupported :test: ~S" test))))
         (remapped-args
           (loop for (k v) on args by #'cddr
                 collect k
                 collect (if (eq k :test) mapped-test v))))
    (apply #'cl:make-hash-table remapped-args)))

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

(cl:defun define-error (name _message &optional _parent)
  "Stub for ELisp `define-error'."
  (declare (ignore _message _parent))
  name)

(cl:defmacro cl-assert (&rest args)
  "Minimal subset of cl-lib's `cl-assert'."
  `(cl:assert ,@args))

(cl:defmacro cl-defmacro (name lambda-list &body body)
  "Minimal subset of cl-lib's `cl-defmacro'."
  `(defmacro ,name ,lambda-list ,@body))

(cl:defmacro cl-defun (name lambda-list &body body)
  "Minimal subset of cl-lib's `cl-defun'."
  `(defun ,name ,lambda-list ,@body))

(cl:defmacro cl-destructuring-bind (lambda-list expr &body body)
  "Minimal subset of cl-lib's `cl-destructuring-bind'."
  `(cl:destructuring-bind ,lambda-list ,expr ,@body))

(cl:defmacro cl-macrolet (bindings &body body)
  "Minimal subset of cl-lib's `cl-macrolet'."
  `(cl:macrolet ,bindings ,@body))

(cl:defmacro cl-flet (bindings &body body)
  "Minimal subset of cl-lib's `cl-flet'."
  `(cl:flet ,bindings ,@body))

(cl:defmacro cl-labels (bindings &body body)
  "Minimal subset of cl-lib's `cl-labels'."
  `(cl:labels ,bindings ,@body))

(cl:defmacro cl-loop (&rest clauses)
  "Minimal subset of cl-lib's `cl-loop'."
  `(cl:loop ,@clauses))

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

(cl:defun cl-remprop (symbol indicator)
  "Minimal subset of cl-lib's `cl-remprop'."
  (and (remprop symbol indicator) t))

(cl:defmacro cl-defstruct (&rest args)
  "Minimal subset of cl-lib's `cl-defstruct'."
  `(cl:defstruct ,@args))

(cl:defun put (symbol prop value)
  "ELisp-ish PUT for symbol plists."
  (setf (get symbol prop) value)
  value)

(defstruct elisp-keymap
  (table (cl:make-hash-table :test 'cl:equal))
  (parent nil))

(defparameter system-type 'darwin)
(defvar *global-map* nil)
(defparameter minibuffer-local-map (make-elisp-keymap))
(defparameter find-function-space-re "")

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

(cl:defun define-key (keymap key definition)
  "Extremely small stub for ELisp `define-key'.

Stores DEFINITION verbatim; KEY can be a string or vector (and is stored as-is)."
  (unless (typep keymap 'elisp-keymap)
    (error "ELISP:DEFINE-KEY expected a keymap, got: ~S" keymap))
  (setf (gethash key (elisp-keymap-table keymap)) definition)
  definition)

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
   ((and (vectorp a) (vectorp b))
    (and (= (length a) (length b))
         (loop for i from 0 below (length a)
               always (equal (aref a i) (aref b i)))))
   (t (cl:equal a b))))

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
    (loop for (var val) on pairs by #'cddr do
      (unless (symbolp var)
        (error "ELISP:SETQ only supports symbol variables, got: ~S" var))
      (push (if (%lexical-variable-p var env)
                `(cl:setq ,var ,val)
                `(set ',var ,val))
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
