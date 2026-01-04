(in-package #:clemacs)

(defun main (&key (stream *standard-output*))
  (format stream "clemacs: hello (SBCL-hosted bring-up scaffold)~%")
  (finish-output stream)
  0)

(defun %arg-has-p (args flag)
  (and (member flag args :test #'string=) t))

(defun %arg-value (args flag)
  (loop for (a b) on args
        when (and (string= a flag) b) do (return b)
        finally (return nil)))

(defun %arg-value/equals (args prefix)
  (loop for a in args
        when (and (stringp a)
                  (<= (length prefix) (length a))
                  (string= prefix a :end2 (length prefix)))
          do (return (subseq a (length prefix)))
        finally (return nil)))

(defun %argv ()
  (or (ignore-errors (cdr sb-ext:*posix-argv*))
      (uiop:command-line-arguments)))

(defun %collect-arg-values (args flag prefix)
  (let ((out nil))
    (loop for (a b) on args do
      (cond
       ((and (stringp a) (string= a flag) (stringp b))
        (push b out))
       ((and (stringp a)
             (<= (length prefix) (length a))
             (string= prefix a :end2 (length prefix)))
        (push (subseq a (length prefix)) out))))
    (nreverse out)))

(defun %batch-eval-string (string &key (stream *standard-output*))
  (let* ((pair (elisp:read-from-string string))
         (form (car pair)))
    (elisp:eval form)
    (finish-output stream)
    0))

(defun %maybe-load-startup-elisp (&key (project-root (uiop:getcwd))
                                      (level "smoke")
                                      (limit nil)
                                      (stream *standard-output*))
  (let* ((manifest (format nil "clemacs/contract/startup.~A.files" level))
         (skip-file "clemacs/contract/lisp.allowed-skip.files"))
    (format stream "[clemacs] loading startup manifest (~A)~%" level)
    (finish-output stream)
    (handler-case
        (elisp:load-elisp-manifest :project-root project-root
                                   :manifest (pathname manifest)
                                   :skip-file (pathname skip-file)
                                   :limit limit)
      (error (e)
        (format *error-output* "[clemacs] startup load failed: ~A~%" e)
        (finish-output *error-output*)
        (return-from %maybe-load-startup-elisp 1))))
  0)

(defun emacs-main (&key (stream *standard-output*))
  "Entry point for the SBCL-hosted `emacs` binary (clemacs).

This is still bring-up quality: it provides a minimal TTY editor loop
and a few batch-friendly flags."
  (let* ((args (%argv))
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
     ((%arg-has-p args "--help")
      (format stream "usage: emacs [--batch] [--version] [--no-elisp]~%")
      (format stream "             [--startup-level {smoke|check|editor-core}] [--startup-limit N] [file]~%")
      (finish-output stream)
      0)
     (batch
      (let* ((no-elisp (%arg-has-p args "--no-elisp"))
             (level (or (%arg-value/equals args "--startup-level=")
                        (%arg-value args "--startup-level")
                        "smoke"))
             (limit-str (or (%arg-value/equals args "--startup-limit=")
                            (%arg-value args "--startup-limit")))
             (limit (and limit-str (parse-integer limit-str :junk-allowed nil)))
             (eval-strings (%collect-arg-values args "--eval" "--eval=")))
        (unless no-elisp
          (let ((rc (%maybe-load-startup-elisp :level level :limit limit :stream stream)))
            (when (not (zerop rc))
              (return-from emacs-main rc))))
        (if eval-strings
            (handler-case
                (progn
                  (dolist (s eval-strings)
                    (%batch-eval-string s :stream stream))
                  0)
              (error (e)
                (format *error-output* "[clemacs] --eval failed: ~A~%" e)
                (finish-output *error-output*)
                1))
            (progn
              (format stream "clemacs: batch mode (not implemented yet)~%")
              (finish-output stream)
              0))))
     (t
      (let* ((no-elisp (%arg-has-p args "--no-elisp"))
             (level (or (%arg-value/equals args "--startup-level=")
                        (%arg-value args "--startup-level")
                        "smoke"))
             (limit-str (or (%arg-value/equals args "--startup-limit=")
                            (%arg-value args "--startup-limit")))
             (limit (and limit-str (parse-integer limit-str :junk-allowed nil))))
        (unless no-elisp
          (let ((rc (%maybe-load-startup-elisp :level level :limit limit :stream stream)))
            (when (not (zerop rc))
              (return-from emacs-main rc))))
        (tty-main :path path))))))
