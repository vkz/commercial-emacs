(in-package #:elisp)

(cl:defun %truthy-env-p (name)
  (let ((v (uiop:getenv name)))
    (and v
         (not (cl:member v '("" "0" "false" "FALSE" "no" "NO")
                         :test #'cl:string=)))))

(define-condition elisp-load-error (cl:error)
  ((path :initarg :path :reader elisp-load-error-path)
   (form-index :initarg :form-index :reader elisp-load-error-form-index)
   (form :initarg :form :reader elisp-load-error-form)
   (cause :initarg :cause :reader elisp-load-error-cause)
   (inventory-entry :initarg :inventory-entry :reader elisp-load-error-inventory-entry))
  (:report (lambda (c s)
             (let* ((cause (elisp-load-error-cause c))
                    (cause-msg
                      (if (typep cause 'elisp-signal)
                          (cl:format nil "signal: (~S . ~S)"
                                     (elisp-signal-symbol cause)
                                     (elisp-signal-data cause))
                          (cl:princ-to-string cause))))
               (cl:format s "ELisp load error in ~A (form ~D):~%  ~S~%~A~@[~%Inventory: ~A~]"
                        (elisp-load-error-path c)
                        (elisp-load-error-form-index c)
                        (elisp-load-error-form c)
                        cause-msg
                        (elisp-load-error-inventory-entry c))))))

(cl:defun %read-noncomment-lines (path)
  (let ((out nil))
    (with-open-file (in path :external-format :utf-8)
      (loop for line = (read-line in nil nil)
            while line do
              (let ((line (cl:string-trim '(#\Space #\Tab #\Return #\Newline) line)))
                (when (and (> (length line) 0)
                           (not (char= (char line 0) #\#)))
                  (push line out)))))
    (nreverse out)))

(cl:defun %split-whitespace (s)
  (let ((tokens nil)
        (start nil))
    (labels ((emit (end)
               (when start
                 (let ((tok (subseq s start end)))
                   (push tok tokens))
                 (setf start nil))))
      (loop for i from 0 below (length s) do
        (let ((ch (char s i)))
          (if (or (char= ch #\Space) (char= ch #\Tab))
              (emit i)
              (unless start
                (setf start i)))))
      (emit (length s)))
    (nreverse tokens)))

(cl:defun %parse-manifest-entry (line)
  "Parse LINE as: <path> [<max-forms>].

Return (values PATH MAX-FORMS), where MAX-FORMS is one of:
- integer: explicit per-file max-forms
- :inherit: no per-file max-forms; inherit the caller's :max-forms (if any)
- :no-limit: explicit '-' in the manifest; do not apply any max-forms limit"
  (let* ((parts (%split-whitespace line))
         (path (first parts))
         (max-forms (second parts)))
    (unless path
      (cl:error "Empty manifest entry"))
    (when (and (third parts))
      (cl:error "Manifest entry has too many fields: ~S" line))
    (cl:values path
               (cond
                ((null max-forms) :inherit)
                ((string= max-forms "-") :no-limit)
                (t
                 (let ((n (parse-integer max-forms :junk-allowed nil)))
                   (and (plusp n) n)))))))

(cl:defun %read-skip-lines (skip-file)
  (let ((out (make-hash-table :test 'cl:equal)))
    (when (and skip-file (probe-file skip-file))
      (dolist (line (%read-noncomment-lines skip-file))
        (multiple-value-bind (path _max) (%parse-manifest-entry line)
          (declare (cl:ignore _max))
          (setf (gethash path out) t))))
    out))

(cl:defun load-elisp-manifest (&key (project-root (uiop:getcwd))
                                    manifest
                                    (skip-file nil)
                                    (ported-root #p"clemacs/ported/")
                                    (limit nil)
                                    (max-forms nil))
  "Load ELisp files listed in MANIFEST.

MANIFEST and SKIP-FILE are interpreted relative to PROJECT-ROOT unless
they are already absolute pathnames.

If a file exists under PORTED-ROOT (relative to PROJECT-ROOT), load the
ported copy instead of the original source tree path."
  (unless manifest
    (cl:error "ELISP:LOAD-ELISP-MANIFEST requires :manifest"))
  (let* ((project-root (uiop:ensure-directory-pathname project-root))
         (manifest (merge-pathnames manifest project-root))
         (skip-file (and skip-file (merge-pathnames skip-file project-root)))
         (ported-root (merge-pathnames ported-root project-root))
         (skips (%read-skip-lines skip-file))
         (loaded 0)
         (show-progress (%truthy-env-p "CLEMACS_LOAD_PROGRESS"))
         (show-timings (%truthy-env-p "CLEMACS_LOAD_TIMINGS")))
    ;; Many upstream libraries rely on `load-path' for `require' and autoloads.
    ;; Populate it with a minimal source-tree + ported-tree search path the
    ;; first time we load a manifest.
    (when (and (boundp 'load-path) (null load-path))
      (setf load-path
            (list
             (namestring (merge-pathnames #p"clemacs/ported/lisp/emacs-lisp/" project-root))
             (namestring (merge-pathnames #p"clemacs/ported/lisp/" project-root))
             (namestring (merge-pathnames #p"lisp/emacs-lisp/" project-root))
             (namestring (merge-pathnames #p"lisp/" project-root)))))
    (setf *clemacs-load-current-rel-path* nil
          *clemacs-load-current-form-index* 0
          *clemacs-load-current-max-forms* nil
          *clemacs-load-current-loaded-count* 0)
    (let* ((async-heartbeat (%truthy-env-p "CLEMACS_LOAD_ASYNC_HEARTBEAT"))
           (async-secs
             (let ((s (uiop:getenv "CLEMACS_LOAD_ASYNC_HEARTBEAT_SECS")))
               (handler-case
                   (let ((n (and s (parse-integer s :junk-allowed t))))
                     (if (and (integerp n) (> n 0)) n 10))
                 (error () 10))))
           (async-backtrace-secs
             (let ((s (uiop:getenv "CLEMACS_LOAD_ASYNC_BACKTRACE_SECS")))
               (handler-case
                   (let ((n (and s (parse-integer s :junk-allowed t))))
                     (and (integerp n) (> n 0) n))
                 (error () nil))))
           (async-backtrace-count
             (let ((s (uiop:getenv "CLEMACS_LOAD_ASYNC_BACKTRACE_COUNT")))
               (handler-case
                   (let ((n (and s (parse-integer s :junk-allowed t))))
                     (if (and (integerp n) (> n 0)) n 50))
                 (error () 50))))
           (stop nil)
           #+sbcl
           (th nil)
           #+sbcl
           (main-thread sb-thread:*current-thread*))
      #+sbcl
      (when async-heartbeat
        (setf th
              (sb-thread:make-thread
               (lambda ()
                 (let ((last-rel nil)
                       (last-idx -1)
                       (last-mf nil)
                       (last-done -1)
                       (stuck-secs 0)
                       (dumped-backtrace nil))
                   (loop until stop do
                     (sleep async-secs)
                     (let ((rel *clemacs-load-current-rel-path*)
                           (idx *clemacs-load-current-form-index*)
                           (mf *clemacs-load-current-max-forms*)
                           (done *clemacs-load-current-loaded-count*))
                       (when rel
                         (cl:format t "[clemacs:load] alive loaded=~D file=~A form=~D~@[ /~D~]~%"
                                    done rel idx mf)
                         (finish-output))
                       (when (and async-backtrace-secs rel)
                         (if (and (equal rel last-rel)
                                  (= idx last-idx)
                                  (= done last-done)
                                  (eql mf last-mf))
                             (incf stuck-secs async-secs)
                             (setf last-rel rel
                                   last-idx idx
                                   last-mf mf
                                   last-done done
                                   stuck-secs 0
                                   dumped-backtrace nil))
                         (when (and (not dumped-backtrace)
                                    (>= stuck-secs async-backtrace-secs))
                           (setf dumped-backtrace t)
                           (ignore-errors
                             (sb-thread:interrupt-thread
                              main-thread
                              (lambda ()
                                (cl:format t "[clemacs:load] backtrace (stuck ~D secs): loaded=~D file=~A form=~D~@[ /~D~]~%"
                                           stuck-secs done rel idx mf)
                                (finish-output)
                                (ignore-errors
                                  (sb-debug:print-backtrace
                                   :stream *standard-output*
                                   :count async-backtrace-count))
                                (finish-output))))))))))
               :name "clemacs-load-heartbeat")))
      (unwind-protect
          (progn
            (dolist (line (%read-noncomment-lines manifest))
              (when (and limit (>= loaded limit))
                (return))
              (multiple-value-bind (rel-path entry-max-forms) (%parse-manifest-entry line)
                (setf *clemacs-load-current-rel-path* rel-path
                      *clemacs-load-current-form-index* 0
                      *clemacs-load-current-max-forms* nil
                      *clemacs-load-current-loaded-count* loaded)
                (cond
                 ((gethash rel-path skips)
                  (cl:format t "[clemacs:load] skip ~A~%" rel-path)
                  (finish-output))
                 (t
                  (let* ((src-path (merge-pathnames rel-path project-root))
                         (ported-path (merge-pathnames rel-path ported-root))
                         (path (if (probe-file ported-path) ported-path src-path))
                         (eff-max-forms
                           (cond
                            ((eq entry-max-forms :no-limit) nil)
                            ((eq entry-max-forms :inherit) max-forms)
                            (t (or entry-max-forms max-forms)))))
                    (setf *clemacs-load-current-max-forms* eff-max-forms)
                    (when show-progress
                      (cl:format t "[clemacs:load] load ~A~@[ max-forms=~D~]~%"
                                 rel-path eff-max-forms)
                      (finish-output))
                    (let ((t0 (and show-timings (get-internal-real-time))))
                      (load-elisp-file path :max-forms eff-max-forms)
                      (when t0
                        (let* ((dt (- (get-internal-real-time) t0))
                               (secs (/ (float dt) internal-time-units-per-second)))
                          (cl:format t "[clemacs:load] done ~A seconds=~,3F~%"
                                     rel-path secs))))
                    (incf loaded)
                    (setf *clemacs-load-current-loaded-count* loaded)))))))
            (setf *clemacs-load-current-rel-path* nil)
            0)
        (setf stop t)
        #+sbcl
        (when th
          (ignore-errors (sb-thread:join-thread th))))))

(cl:defun load-bootstrap-set (&key (project-root (uiop:getcwd))
                                   (manifest #p"clemacs/contract/bootstrap.files")
                                   (limit nil)
                                   (max-forms nil))
  "Backwards-compatible wrapper for the initial ELisp bootstrap manifest."
  (load-elisp-manifest :project-root project-root
                       :manifest manifest
                       :limit limit
                       :max-forms max-forms))
