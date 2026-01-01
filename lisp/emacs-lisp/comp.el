;;; comp.el --- ELisp native compilation stubs  -*- lexical-binding: t; -*-

;; This file is NOT part of GNU Emacs.

;;; Commentary:

;; This fork disables ELisp native compilation (libgccjit).  Keep a small
;; compatibility layer so callers can load `comp' and get clear errors.

;;; Code:

(defvar no-byte-compile nil
  "Non-nil means inhibit byte compilation for the current file.")
(put 'no-byte-compile 'safe-local-variable 'booleanp)

(defvar no-native-compile nil
  "Non-nil means inhibit ELisp native compilation for the current file.")
(put 'no-native-compile 'safe-local-variable 'booleanp)

(defun native-compile (&rest _args)
  "Signal that native compilation is unavailable in this fork."
  (user-error "Native compilation is disabled in this fork"))

(defun batch-native-compile (&rest _args)
  "Signal that native compilation is unavailable in this fork."
  (user-error "Native compilation is disabled in this fork"))

(defun package-native-compile (&rest _args)
  "Signal that native compilation is unavailable in this fork."
  (user-error "Native compilation is disabled in this fork"))

(defun comp-subr-trampoline-install (&rest _args)
  "Signal that native compilation is unavailable in this fork."
  (user-error "Native compilation is disabled in this fork"))

(provide 'comp)

;;; comp.el ends here
