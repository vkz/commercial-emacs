;;; cl-preloaded.el --- Preloaded part of the CL library (ported for clemacs)  -*- lexical-binding: t; -*-

;; This is a clemacs-local port of upstream `lisp/emacs-lisp/cl-preloaded.el`.
;;
;; Rationale (2026-01-05):
;; - The upstream file bootstraps Emacs's own cl-lib struct/type-descriptor
;;   machinery via a circular `cl--find-class` setup.
;; - clemacs is CL-hosted and uses CL:DEFSTRUCT directly, so we don't want to
;;   recreate Emacs's cl-lib struct metaobject model during bring-up.
;;
;; This file intentionally defines only a minimal subset needed by early
;; startup and upstream ERT/cl-lib bring-up.

;;; Code:

(define-error 'cl-assertion-failed "Assertion failed")

(defun cl--assertion-failed (form &optional string sargs args)
  "Signal a `cl-assertion-failed' error.

This is a clemacs bring-up subset; it does not integrate with Emacs's debugger."
  (if string
      (apply #'error string (append sargs args))
    (signal 'cl-assertion-failed (cons form sargs))))

(defun cl--builtin-type-p (_name)
  "Return non-nil if NAME is a built-in class.

Bring-up stub for clemacs: we do not model Emacs's built-in-class-p yet."
  nil)

(defun cl--struct-name-p (name)
  "Return t if NAME is a valid structure name for `cl-defstruct'.

Bring-up stub: accept non-keyword symbols."
  (and name (symbolp name) (not (keywordp name))))

;; Provide CL-ish struct types as plain CL:DEFSTRUCTs.
;;
;; These are intentionally much simpler than upstream's type-descriptor model,
;; but they unblock loading more of cl-lib without requiring the circular
;; cl-preloaded bootstrap.

(cl:defstruct (cl-slot-descriptor
               (:conc-name cl--slot-descriptor-))
  name
  initform
  type
  props)

(cl:defstruct (cl--class
               (:constructor nil)
               (:copier nil))
  name
  docstring
  parents
  slots
  index-table)

(cl:defstruct (cl-structure-class
               (:include cl--class)
               (:conc-name cl--struct-class-)
               (:constructor nil)
               (:copier nil))
  tag
  type
  named
  print
  children-sym)

(cl:defstruct (cl-structure-object
               (:constructor nil)
               (:copier nil)))

;; Upstream sets this during its circular bootstrap; we keep the name and a
;; reasonable default for downstream code that checks it.
(defvar cl--struct-default-parent 'cl-structure-object)

(provide 'cl-preloaded)

;;; cl-preloaded.el ends here
