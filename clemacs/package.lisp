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
           #:make-list #:format
           #:append
           #:prin1-to-string #:read-from-string
           #:string= #:string-equal
           #:characterp
           #:type-of
           #:symbol-function #:symbol-name #:fboundp #:values #:symbol-value
           #:signal #:handler-bind #:error
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
