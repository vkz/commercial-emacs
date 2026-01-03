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
