(in-package #:clemacs.test)

(defun run-smoke (&key (stream *standard-output*))
  (format stream "clemacs smoke: ok~%")
  (finish-output stream)
  0)
