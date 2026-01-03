(in-package #:clemacs)

(define-condition clemacs-error (error) ())

(define-condition clemacs-quit (clemacs-error) ()
  (:report (lambda (c s)
             (declare (ignore c))
             (write-string "clemacs quit" s))))

(define-condition clemacs-substrate-error (clemacs-error)
  ((status :initarg :status :reader clemacs-substrate-error-status)
   (message :initarg :message :reader clemacs-substrate-error-message))
  (:report (lambda (c s)
             (format s "clemacs substrate error (~A): ~A"
                     (clemacs-substrate-error-status c)
                     (clemacs-substrate-error-message c)))))
