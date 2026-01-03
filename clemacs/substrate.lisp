(in-package #:clemacs)

(defvar *substrate-loaded* nil)

(defun substrate-dylib-path ()
  (or (uiop:getenv "CLEMACS_SUBSTRATE_DYLIB")
      (error "CLEMACS_SUBSTRATE_DYLIB is not set")))

(defun ensure-substrate-loaded ()
  (unless *substrate-loaded*
    (cffi:load-foreign-library (substrate-dylib-path))
    (setf *substrate-loaded* t)))

(cffi:defcfun ("emx_substrate_version" %emx-substrate-version) :string)
(cffi:defcfun ("emx_substrate_platform" %emx-substrate-platform) :string)
(cffi:defcfun ("emx_substrate_status_string" %emx-substrate-status-string) :string
  (status :int32))
(cffi:defcfun ("emx_substrate_parse_int" %emx-substrate-parse-int) :int32
  (s :string)
  (out :pointer))
(cffi:defcfun ("emx_tty_enter_raw" %emx-tty-enter-raw) :int32)
(cffi:defcfun ("emx_tty_exit_raw" %emx-tty-exit-raw) :int32)
(cffi:defcfun ("emx_tty_read_byte" %emx-tty-read-byte) :int32
  (out :pointer))
(cffi:defcfun ("emx_tty_write" %emx-tty-write) :int32
  (buf :pointer)
  (len :int32))
(cffi:defcfun ("emx_tty_get_winsize" %emx-tty-get-winsize) :int32
  (out-rows :pointer)
  (out-cols :pointer))

(defun %check-substrate-status (status)
  (cond
   ((= status 0) nil)
   ((= status 2) (error 'clemacs-quit))
   (t (error 'clemacs-substrate-error
             :status status
             :message (%emx-substrate-status-string status)))))

(defun substrate-version ()
  (ensure-substrate-loaded)
  (%emx-substrate-version))

(defun substrate-platform ()
  (ensure-substrate-loaded)
  (%emx-substrate-platform))

(defun substrate-parse-int (s)
  (ensure-substrate-loaded)
  (cffi:with-foreign-object (out :int32)
    (%check-substrate-status (%emx-substrate-parse-int s out))
    (cffi:mem-ref out :int32)))

(defun tty-enter-raw ()
  (ensure-substrate-loaded)
  (%check-substrate-status (%emx-tty-enter-raw)))

(defun tty-exit-raw ()
  (ensure-substrate-loaded)
  (%check-substrate-status (%emx-tty-exit-raw)))

(defun tty-read-byte ()
  (ensure-substrate-loaded)
  (cffi:with-foreign-object (out :uint8)
    (%check-substrate-status (%emx-tty-read-byte out))
    (cffi:mem-ref out :uint8)))

(defun tty-write-string (s)
  (ensure-substrate-loaded)
  (let ((octets (babel:string-to-octets s :encoding :utf-8)))
    (cffi:with-pointer-to-vector-data (ptr octets)
      (%check-substrate-status (%emx-tty-write ptr (length octets))))))

(defun tty-winsize ()
  (ensure-substrate-loaded)
  (cffi:with-foreign-objects ((rows :int32) (cols :int32))
    (%check-substrate-status (%emx-tty-get-winsize rows cols))
    (values (cffi:mem-ref rows :int32) (cffi:mem-ref cols :int32))))
