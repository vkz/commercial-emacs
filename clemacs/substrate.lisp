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

(defun substrate-version ()
  (ensure-substrate-loaded)
  (%emx-substrate-version))

(defun substrate-platform ()
  (ensure-substrate-loaded)
  (%emx-substrate-platform))
