;;; comp-common.el --- ELisp native compilation stubs  -*- lexical-binding: t; -*-

;; This file is NOT part of GNU Emacs.

;;; Commentary:

;; Stub helpers for code that expects `comp-common' to exist.

;;; Code:

(defun comp-function-type-spec (function)
  "Return a minimal type spec for FUNCTION.

Native compilation is disabled in this fork, so no type inference is
performed."
  (cons function 'inferred))

(provide 'comp-common)

;;; comp-common.el ends here
