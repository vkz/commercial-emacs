(defpackage #:clemacs
  (:use #:cl)
  (:export
   #:main
   #:substrate-platform
   #:substrate-version))

(defpackage #:clemacs.test
  (:use #:cl)
  (:export #:run-smoke))
