(defpackage #:clemacs
  (:use #:cl)
  (:export
   #:clemacs-error
   #:clemacs-quit
   #:clemacs-substrate-error
   #:clemacs-substrate-error-message
   #:clemacs-substrate-error-status
   #:emx-value
   #:handle-alloc
   #:handle-free
   #:handle-get
   #:handle-table
   #:make-handle-table
   #:main
   #:make-buffer
   #:buffer
   #:buffer-path
   #:buffer-text
   #:buffer-point
   #:buffer-length
   #:buffer-insert-char
   #:buffer-insert-string
   #:buffer-delete-backward
   #:buffer-forward-char
   #:buffer-backward-char
   #:buffer-move-vertical
   #:buffer-load-file
   #:buffer-save
   #:list-upstream-ert-test-names
   #:run-upstream-ert-tests
   #:tty-main
   #:emacs-main
   #:substrate-platform
   #:substrate-parse-int
   #:substrate-version))

(defpackage #:clemacs.test
  (:use #:cl)
  (:export #:run-smoke))

(defpackage #:elisp
  (:use #:cl)
  (:shadow #:defmacro #:defun #:equal #:eval #:funcall #:function #:intern #:make-hash-table #:provide #:require #:setq
           #:defvar #:defconst
           #:make-symbol
           #:gensym
           #:make-list #:format
           #:make-string
           #:string
           #:load
           #:+ #:-
           #:ignore
           #:1+ #:1-
           #:append
           #:member
           #:mapcar
           #:prin1 #:princ #:prin1-to-string #:princ-to-string #:read-from-string
           #:string= #:string-equal
           #:aref
           #:stringp
           #:vectorp
           #:characterp
           #:type-of
	           #:symbol-function #:symbol-name #:fboundp #:values #:symbol-value
	           #:signal #:handler-bind #:error
	           #:< #:<= #:= #:> #:>=
	           ;; Preserve Emacs-Lisp declaration names as ELISP package symbols.
	           #:advertised-calling-convention
	           #:compiler-macro
	           #:completion
	           #:debug
	           #:doc-string
	           #:indent
	           #:important-return-value
	           #:interactive-only
	           #:obsolete
	           #:pure
	           #:side-effect-free
	           #:set)
	  (:export
	   #:equal
   #:eval
   #:load-elisp-file
   #:load-elisp-manifest
   #:load-bootstrap-set
   #:ert-deftest
   #:ert-run-tests-batch
   #:ert-reset
   #:should
   #:plist-get
   #:plist-put
   #:prin1-to-string
   #:read-from-string))

;; Package namespace stubs used by upstream ELisp symbol names like `GUI:bottom`.
;; In Emacs Lisp, `:' is just a symbol constituent, but our current reader uses
;; CL package syntax.  Defining these packages is a pragmatic bring-up hack.
(defpackage #:gui
  (:use)
  (:export
   #:bottom
   #:font
   #:fullscreen
   #:height
   #:left
   #:right
   #:top
   #:width))
