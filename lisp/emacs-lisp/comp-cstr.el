;;; comp-cstr.el --- ELisp native compilation stubs  -*- lexical-binding: t; -*-

;; This file is NOT part of GNU Emacs.

;;; Commentary:

;; Stub module for code that expects `comp-cstr' to exist.

;;; Code:

(defmacro with-comp-cstr-accessors (&rest _body)
  "Signal that native compilation is unavailable in this fork."
  (declare (indent 0))
  (error "Native compilation is disabled in this fork"))

(provide 'comp-cstr)

;;; comp-cstr.el ends here
