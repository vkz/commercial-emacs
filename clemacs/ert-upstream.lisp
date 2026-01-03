(in-package #:clemacs)

(defun %elisp-symbol (name)
  (let* ((pkg (find-package "ELISP"))
         (s (etypecase name
              (symbol (symbol-name name))
              (string name))))
    (intern (string-upcase s) pkg)))

(defun %upstream-ert-test (name)
  (let* ((sym (%elisp-symbol name))
         (test (get sym 'elisp::ert--test)))
    (unless test
      (error "No upstream ERT test registered for ~S (symbol ~S)" name sym))
    test))

(defun %maybe-upstream-ert-condition (result)
  (labels ((try (fn &rest args)
             (when (fboundp fn)
               (handler-case
                   (apply fn args)
                 (error () nil)))))
    (or (try 'elisp::ert-test-result-with-condition-condition result)
        (try 'elisp::ert-test-failed-condition result)
        (try 'elisp::ert-test-skipped-condition result))))

(defun run-upstream-ert-tests (&key (names '("ert-test-body-runs"))
                                    (known-fail nil)
                                    (stream *standard-output*))
  "Run a small, explicit set of upstream ERT tests under clemacs.

This is an incremental bring-up gate: we run named tests via upstream
`ert-run-test' without depending on windows/buffers/UI."
  (unless (fboundp 'elisp::ert-run-test)
    (error "Upstream ERT is not loaded (missing ELISP::ERT-RUN-TEST)"))
  (unless (fboundp 'elisp::ert-test-passed-p)
    (error "Upstream ERT is not loaded (missing ELISP::ERT-TEST-PASSED-P)"))

  (let ((debugp (and (uiop:getenv "CLEMACS_ERT_DEBUG") t))
        (total 0)
        (failed 0)
        (xfail 0)
        (xpass 0))
    (dolist (name names)
      (incf total)
      (handler-case
          (let* ((test (%upstream-ert-test name))
                 (result (funcall 'elisp::ert-run-test test))
                 (ok (funcall 'elisp::ert-test-passed-p result))
                 (expected-fail (member name known-fail :test #'string=)))
            (cond
             ((and expected-fail ok)
              (incf xpass)
              (format stream "XPASS ~A~%" name)
              (when debugp
                (format stream "      ~S~%" (%maybe-upstream-ert-condition result))))
             ((and expected-fail (not ok))
              (incf xfail)
              (format stream "XFAIL ~A~%" name)
              (when debugp
                (format stream "      ~S~%" (%maybe-upstream-ert-condition result))))
             (ok
              (format stream "ok   ~A~%" name))
             (t
              (incf failed)
              (format stream "FAIL ~A~%" name)
              (when debugp
                (format stream "      ~S~%" (%maybe-upstream-ert-condition result))))))
        (error (e)
          (if (member name known-fail :test #'string=)
              (progn
                (incf xfail)
                (format stream "XFAIL ~A: ~A~%" name e))
              (progn
                (incf failed)
                (format stream "ERROR ~A: ~A~%" name e))))))
    (format stream "clemacs upstream ert: ~D total, ~D failed, ~D xfail, ~D xpass~%"
            total failed xfail xpass)
    (finish-output stream)
    (if (and (zerop failed) (zerop xpass)) 0 1)))
