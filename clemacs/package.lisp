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
   #:tty-main
   #:substrate-platform
   #:substrate-parse-int
   #:substrate-version))

(defpackage #:clemacs.test
  (:use #:cl)
  (:export #:run-smoke))

(defpackage #:elisp
  (:use #:cl)
  (:shadow #:setq)
  (:export
   #:load-elisp-file
   #:plist-get
   #:plist-put))
