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

;; ---------------------------------------------------------------------------
;; cl-generic integration (type descriptors)
;;
;; Upstream `cl-generic` dispatches on OClosure-defined types by consulting
;; `cl--find-class` and checking for an `oclosure--class` descriptor.  This
;; clemacs-local port models OClosures as host CLOS classes, but we still
;; register lightweight `oclosure--class` descriptors so downstream ELisp
;; (notably `lisp/simple.el`) can define `cl-defmethod` specializers like
;; `accessor`.
;; ---------------------------------------------------------------------------

(eval-when (:load-toplevel :execute)
  ;; `cl--class` is defined by `lisp/emacs-lisp/cl-preloaded.el`, which is not
  ;; always loaded in the smallest smoke manifests.  Define the descriptor type
  ;; only when the base class is available.
  (when (cl:find-class 'cl--class nil)
    (cl:eval
     '(progn
        (cl:defun %clemacs-oclosure--index-table (slotdescs)
          (let ((it (make-hash-table :test 'eq)))
            (when (vectorp slotdescs)
              (dotimes (i (length slotdescs))
                (let ((desc (aref slotdescs i)))
                  (when desc
                    (setf (gethash (cl--slot-descriptor-name desc) it) i)))))
            it))

        (cl-defstruct (oclosure--class
                       (:constructor nil)
                       (:constructor oclosure--class-make
                        ( name docstring slots parents allparents
                          &aux (index-table (%clemacs-oclosure--index-table slots))))
                       (:include cl--class)
                       (:copier nil))
          "Type descriptor for ported OClosure types (for cl-generic dispatch)."
          (allparents nil :read-only t :type list))))))

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

(cl:defmethod oclosure-type ((o t))
  (declare (ignore o))
  nil)

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

(eval-when (:load-toplevel :execute)
  (when (and (fboundp 'cl--find-class) (fboundp 'oclosure--class-make))
    (labels ((allparents (name parent)
               (if (and parent (fboundp 'cl--class-allparents))
                   (cons name (cl--class-allparents parent))
                   (list name))))
      (let* ((closure-class (ignore-errors (cl--find-class 'closure)))
             (slots (cl:make-array 0))
             (oclosure-desc
              (oclosure--class-make
               'oclosure
               "Type descriptor for ported OClosures."
               slots
               (if closure-class (list closure-class) nil)
               (allparents 'oclosure closure-class))))
        (setf (cl--find-class 'oclosure) oclosure-desc)
        (setf (cl--find-class 'accessor)
              (oclosure--class-make
               'accessor
               "Type descriptor for ported accessors."
               slots
               (list oclosure-desc)
               (allparents 'accessor oclosure-desc)))
        (setf (cl--find-class 'cconv--interactive-helper)
              (oclosure--class-make
               'cconv--interactive-helper
               "Type descriptor for cconv interactive helper oclosures."
               slots
               (list oclosure-desc)
               (allparents 'cconv--interactive-helper oclosure-desc)))))))

(provide 'oclosure)

;;; oclosure.el ends here
