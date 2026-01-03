(in-package #:clemacs)

(defun main (&key (stream *standard-output*))
  (format stream "clemacs: hello (SBCL-hosted bring-up scaffold)~%")
  (finish-output stream)
  0)

(defun emacs-main (&key (stream *standard-output*))
  "Entry point for the SBCL-hosted `emacs` binary (clemacs).

This is still bring-up quality: it provides a minimal TTY editor loop
and a few batch-friendly flags."
  (let* ((args (uiop:command-line-arguments))
         (path (loop for a in args
                     unless (and (stringp a) (> (length a) 0) (char= (char a 0) #\-))
                     do (return a)))
         (batch (member "--batch" args :test #'string=))
         (version (or (member "--version" args :test #'string=)
                      (member "-V" args :test #'string=))))
    (cond
     (version
      (format stream "clemacs (SBCL-hosted)~%")
      (format stream "substrate: ~A (~A)~%" (substrate-version) (substrate-platform))
      (finish-output stream)
      0)
     (batch
      (format stream "clemacs: batch mode (not implemented yet)~%")
      (finish-output stream)
      0)
     (t
      (tty-main :path path)))))
