(in-package #:clemacs.test)

(defun %assert (pred fmt &rest args)
  (unless pred
    (error "~?." fmt args)))

(defun run-smoke (&key (stream *standard-output*))
  (let ((version (clemacs:substrate-version))
        (platform (clemacs:substrate-platform)))
    (%assert (and (stringp version) (> (length version) 0))
             "substrate version is invalid: ~S" version)
    (%assert (and (stringp platform) (> (length platform) 0))
             "substrate platform is invalid: ~S" platform))
  (format stream "clemacs smoke: ok~%")
  (finish-output stream)
  0)
