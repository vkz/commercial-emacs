(in-package #:cl-user)

;; This file is a convenience loader for REPL use.
;;
;; The clemacs ASDF system now loads the compat implementation from:
;;   clemacs/elisp-compat/*.lisp
;;
;; If you load this file directly, ensure the ELISP package exists first.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "ELISP")
    (error "ELISP package is not defined; load the clemacs system first")))

(in-package #:elisp)

(labels ((load-here (relative)
           (load (merge-pathnames relative (or *load-pathname* *compile-file-pathname*)))))
  (load-here "elisp-compat/00-core.lisp")
  (load-here "elisp-compat/10-strings.lisp")
  (load-here "elisp-compat/20-regexp-rx-print.lisp")
  (load-here "elisp-compat/30-pcase.lisp")
  (load-here "elisp-compat/40-cl-lib-and-charset.lisp")
  (load-here "elisp-compat/50-keymaps-runtime-help.lisp")
  (load-here "elisp-compat/60-files.lisp")
  (load-here "elisp-compat/70-buffers-and-editor.lisp")
  (load-here "elisp-compat/80-ewoc.lisp")
  (load-here "elisp-compat/90-messages-and-macroexp.lisp")
  (load-here "elisp-compat/99-rest.lisp"))
