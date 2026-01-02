(in-package #:clemacs)

(defun main (&key (stream *standard-output*))
  (format stream "clemacs: hello (SBCL-hosted bring-up scaffold)~%")
  (finish-output stream)
  0)
