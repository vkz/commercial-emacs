;;; oclosure.el --- Open Closures (ported for clemacs) -*- lexical-binding: t; -*-

;; This is a clemacs-local port of upstream `lisp/emacs-lisp/oclosure.el`.
;;
;; Rationale (2026-01-06):
;; - clemacs uses host CLOS for `cl-generic` bring-up (`cl-defmethod` expands to
;;   host `cl:defmethod`), so method specializers must be real CLOS classes.
;; - Upstream `oclosure.el` depends on Emacs's closure/bytecode vector
;;   substrate (`closurep`, interpreted closure layout, etc.), which clemacs
;;   does not model yet.
;; - For bring-up, we provide a small, SBCL-only, funcallable-CLOS subset that
;;   unblocks loading more of `lisp/simple.el` (notably `accessor` and
;;   `cconv--interactive-helper`).

;;; Code:

(in-package #:elisp)

#+sbcl
(progn
  (cl:defclass oclosure (sb-mop:funcallable-standard-object)
    ((%oclosure-type :initarg :oclosure-type :reader oclosure-type)
     (%call :initarg :call :accessor %oclosure-call))
    (:metaclass sb-mop:funcallable-standard-class))

  (cl:defmethod initialize-instance :after ((o oclosure) &key)
    (sb-mop:set-funcallable-instance-function o (%oclosure-call o))))

#-sbcl
(progn
  (cl:defclass oclosure ()
    ((%oclosure-type :initarg :oclosure-type :reader oclosure-type)
     (%call :initarg :call :accessor %oclosure-call))))

(cl:defclass accessor (oclosure)
  ((%accessor-type :initarg :type :reader accessor--type)
   (%accessor-slot :initarg :slot :reader accessor--slot)))

(cl:defun oclosure--accessor-docstring (f)
  (format "Access slot \"%S\" of OBJ of type `%S'.\n\n(fn OBJ)"
          (accessor--slot f) (accessor--type f)))

;; NOTE: We intentionally do not define (a function) `oclosure-accessor` yet.
;; Upstream defines `oclosure-accessor` as an oclosure *type* name (not a
;; constructor).  The bring-up subset here only needs the `accessor` type for
;; `cl-defmethod` dispatch and docstring generation.

(cl:defclass cconv--interactive-helper (oclosure)
  ((%fun :initarg :fun :reader cconv--interactive-helper--fun)
   (%if-form :initarg :if :reader cconv--interactive-helper--if)))

(cl:defun cconv--interactive-helper (fun if)
  "Add interactive \"form\" IF to FUN.
Returns a new command that otherwise behaves like FUN.
IF can be an ELisp form to be interpreted or a function of no arguments."
  (make-instance 'cconv--interactive-helper
                 :oclosure-type 'cconv--interactive-helper
                 :fun fun
                 :if if
                 :call (lambda (&rest args)
                         (apply #'funcall fun args))))

(provide 'oclosure)

;;; oclosure.el ends here
