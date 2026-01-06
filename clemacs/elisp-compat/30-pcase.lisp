(in-package #:elisp)

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
    (unless (and (listp parent-conds) (cl:member parent parent-conds :test #'eq))
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
