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

(defun %maybe-upstream-ert-backtrace (result)
  (labels ((try (fn &rest args)
             (when (fboundp fn)
               (handler-case
                   (apply fn args)
                 (error () nil)))))
    (or (try 'elisp::ert-test-result-with-condition-backtrace result)
        nil)))

(defun %debug-print-upstream-ert-condition (result &key (stream *standard-output*))
  (let ((c (%maybe-upstream-ert-condition result)))
    (format stream "      ~S~%" c)
    ;; Sometimes we stash raw CL SIMPLE-CONDITION objects inside ELisp
    ;; `(error . DATA)` signals.  When present, printing the format args makes
    ;; the underlying cause (e.g. wrong argcount) actionable.
    (when (and (consp c) (consp (cdr c)) (typep (cadr c) 'simple-condition))
      (let ((sc (cadr c)))
        (format stream "      cl:simple-condition control: ~S~%"
                (ignore-errors (simple-condition-format-control sc)))
        (format stream "      cl:simple-condition args: ~S~%"
                (ignore-errors (simple-condition-format-arguments sc))))))
  (finish-output stream))

(defun list-upstream-ert-test-names (&key (stream *standard-output*))
  "Return the list of upstream ERT tests currently registered under clemacs.

This scans the ELISP package for symbols with an `ert--test` property."
  (let* ((pkg (find-package "ELISP"))
         (names nil))
    (do-symbols (s pkg)
      (when (get s 'elisp::ert--test)
        (push (string-downcase (symbol-name s)) names)))
    (setf names (sort names #'string<))
    (dolist (n names)
      (format stream "~A~%" n))
    (finish-output stream)
    names))

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
  (unless (fboundp 'elisp::ert-test-result-expected-p)
    (error "Upstream ERT is not loaded (missing ELISP::ERT-TEST-RESULT-EXPECTED-P)"))

  (let ((debugp (and (uiop:getenv "CLEMACS_ERT_DEBUG") t))
        (timeout-secs
          (let ((s (uiop:getenv "CLEMACS_ERT_TEST_TIMEOUT_SECS")))
            (cond
             ((null s) 30)
             ((string= s "") 30)
             (t (parse-integer s)))))
        (total 0)
        (failed 0)
        (xfail 0)
        (xpass 0))
    (dolist (name names)
      (incf total)
      (format stream "RUN  ~A~%" name)
      (finish-output stream)
      (handler-case
          (handler-bind
              ((error
                 (lambda (e)
                   (when debugp
                     (format stream "      signalled: ~A~%" e)
                     #+sbcl
                     (sb-debug:print-backtrace :stream stream :count 50))
                   nil))
               (elisp::elisp-signal
                 (lambda (c)
                   (when debugp
                     (format stream "      elisp-signal: ~S ~S~%"
                             (ignore-errors (elisp::elisp-signal-symbol c))
                             (ignore-errors (elisp::elisp-signal-data c)))
                     #+sbcl
                     (sb-debug:print-backtrace :stream stream :count 50))
                   nil)))
            (let* ((test (%upstream-ert-test name))
                   (result
                     #+sbcl
                     (if (and (integerp timeout-secs) (plusp timeout-secs))
                         (let* ((values nil)
                                (err nil)
                                (thr
                                  (sb-thread:make-thread
                                   (lambda ()
                                     (handler-case
                                         (setf values (multiple-value-list
                                                       (funcall 'elisp::ert-run-test test)))
                                       (error (e) (setf err e)))))))
                           (multiple-value-bind (default why)
                               (sb-thread:join-thread thr :timeout timeout-secs :default :timeout)
                             (cond
                              ((eq why :timeout)
                               (format stream "TIMEOUT ~A (~Ds)~%" name timeout-secs)
                               (finish-output stream)
                               (ignore-errors
                                (sb-thread:interrupt-thread
                                 thr
                                 (lambda ()
                                   (format stream "      backtrace (timeout):~%")
                                    (ignore-errors
                                     (let* ((buf elisp::*current-buffer*)
                                            (txt (and (typep buf 'elisp::elisp-buffer)
                                                      (elisp::elisp-buffer-text buf)))
                                            (pt (and (typep buf 'elisp::elisp-buffer)
                                                     (elisp::elisp-buffer-point buf)))
                                            (nm (and (typep buf 'elisp::elisp-buffer)
                                                     (elisp::elisp-buffer-name buf))))
                                      (format stream "      buffer: ~S point=~S len=~S edits=~S~%"
                                              (ignore-errors (elisp::%elisp-string->cl-string nm))
                                              pt
                                              (and (stringp txt) (length txt))
                                              (and (typep buf 'elisp::elisp-buffer)
                                                   (fill-pointer (elisp::elisp-buffer-marker-edits buf))))
                                      (when (and (stringp txt) (integerp pt))
                                        (let* ((idx (max 0 (min (length txt) (1- pt))))
                                               (a (max 0 (- idx 80)))
                                               (b (min (length txt) (+ idx 80))))
                                          (format stream "      around point: ~S~%"
                                                  (substitute #\Space #\Newline (subseq txt a b)))))))
                                    (sb-debug:print-backtrace :stream stream :count 80)
                                    (finish-output stream))))
                               (sleep 0.05)
                               (ignore-errors (sb-thread:terminate-thread thr))
                               (error "Timed out after ~D seconds" timeout-secs))
                              ((eq why :abort)
                               (error "Test thread aborted: ~S" default))
                              (err
                               (error err))
                              (t
                               (values-list values)))))
                         (funcall 'elisp::ert-run-test test))
                     #-sbcl
                     (funcall 'elisp::ert-run-test test))
                   (passedp (funcall 'elisp::ert-test-passed-p result))
                   (expectedp (funcall 'elisp::ert-test-result-expected-p test result))
                   (skippedp (and (fboundp 'elisp::ert-test-skipped-p)
                                  (funcall 'elisp::ert-test-skipped-p result)))
                   (expected-fail (member name known-fail :test #'string=)))
              (cond
               ;; Manual known-fail list always wins (treat XPASS as a failure).
               (expected-fail
                (cond
                 ((and passedp (not skippedp))
                  (incf xpass)
                  (format stream "XPASS ~A~%" name)
                  (when debugp
                    (let ((bt (%maybe-upstream-ert-backtrace result)))
                      (when bt
                        (format stream "      backtrace:~%      ~S~%" bt)))
                    (%debug-print-upstream-ert-condition result :stream stream)))
                 (t
                  (incf xfail)
                  (format stream "XFAIL ~A~%" name)
                  (when debugp
                    (let ((bt (%maybe-upstream-ert-backtrace result)))
                      (when bt
                        (format stream "      backtrace:~%      ~S~%" bt)))
                    (%debug-print-upstream-ert-condition result :stream stream)))))

               ;; Skips are "expected" in upstream ERT.
               (skippedp
                (incf xfail)
                (format stream "SKIP ~A~%" name)
                (when debugp
                  (%debug-print-upstream-ert-condition result :stream stream)))

               ;; ERT-level expected results (e.g. :expected-result :failed).
               (expectedp
                (cond
                 (passedp
                  (format stream "ok   ~A~%" name))
                 (t
                  (incf xfail)
                  (format stream "XFAIL ~A~%" name)
                  (when debugp
                    (let ((bt (%maybe-upstream-ert-backtrace result)))
                      (when bt
                        (format stream "      backtrace:~%      ~S~%" bt)))
                    (%debug-print-upstream-ert-condition result :stream stream)))))

               ;; Unexpected results.
               (passedp
                (incf xpass)
                (format stream "XPASS ~A~%" name))
               (t
                (incf failed)
                (format stream "FAIL ~A~%" name)
                (when debugp
                  (let ((bt (%maybe-upstream-ert-backtrace result)))
                    (when bt
                      (format stream "      backtrace:~%      ~S~%" bt)))
                  (%debug-print-upstream-ert-condition result :stream stream))))))
        (error (e)
          (if (member name known-fail :test #'string=)
              (progn
                (incf xfail)
                (format stream "XFAIL ~A: ~A~%" name e))
              (progn
                (incf failed)
                (format stream "ERROR ~A: ~A~%" name e)
                (when debugp
                  (format stream "      (~A)~%" (type-of e))
                  #+sbcl
                  (sb-debug:print-backtrace :stream stream :count 50)))))))
    (format stream "clemacs upstream ert: ~D total, ~D failed, ~D xfail, ~D xpass~%"
            total failed xfail xpass)
    (finish-output stream)
    (if (and (zerop failed) (zerop xpass)) 0 1)))
