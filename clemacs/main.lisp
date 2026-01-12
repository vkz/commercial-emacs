(in-package #:clemacs)

(defun main (&key (stream *standard-output*))
  (format stream "clemacs: hello (SBCL-hosted bring-up scaffold)~%")
  (finish-output stream)
  0)

(defun %usage (&key (stream *standard-output*) (exit-code 0) (error nil))
  (when error
    (format *error-output* "~A~%" error)
    (finish-output *error-output*))
  (format stream "usage: emacs [options] [file]~%")
  (format stream "~%")
  (format stream "core options (subset):~%")
  (format stream "  --help, -h           Show this help and exit.~%")
  (format stream "  --version, -V        Show version and exit.~%")
  (format stream "  --batch              Noninteractive mode (load startup, run --eval, exit).~%")
  (format stream "  --eval EXPR          Evaluate an Emacs Lisp form (repeatable).~%")
  (format stream "  -Q                   Skip user init (and site init; site init not implemented yet).~%")
  (format stream "  -q                   Skip user init.~%")
  (format stream "~%")
  (format stream "clemacs options:~%")
  (format stream "  --no-elisp           Skip loading shipped ELisp startup manifests.~%")
  (format stream "  --startup-level L    Startup manifest: smoke|check|tty-editor|editor-core.~%")
  (format stream "  --startup-limit N    Limit load to N top-level forms per file (debugging).~%")
  (format stream "~%")
  (format stream "unsupported (for now):~%")
  (format stream "  -l/--load, -f, --script, --daemon, --debug-init, --init-directory, and most other Emacs flags.~%")
  (finish-output stream)
  exit-code)

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

(defun %parse-argv (args)
  "Parse a minimal Emacs-shaped argv list ARGS.

Returns a plist with keys:
  :batch :help :version :no-elisp :quick :no-init
  :startup-level :startup-limit :eval-strings :file :unknown-flags"
  (let ((batch nil)
        (help nil)
        (version nil)
        (no-elisp nil)
        (quick nil)
        (no-init nil)
        (startup-level nil)
        (startup-limit nil)
        (eval-strings nil)
        (file nil)
        (unknown nil))
    (labels ((take-next (i)
               (let ((n (nth (1+ i) args)))
                 (unless (and n (stringp n))
                   (return-from %parse-argv
                     (list :parse-error (format nil "missing value after ~A" (nth i args)))))
                 n))
             (parse-int (s opt)
               (handler-case
                   (parse-integer s :junk-allowed nil)
                 (error ()
                 (return-from %parse-argv
                   (list :parse-error (format nil "bad integer for ~A: ~S" opt s)))))))
      (let ((i 0)
            (n (length args)))
        (loop while (< i n) do
          (let ((a (nth i args)))
            (cond
             ((null a) nil)
             ((string= a "--") ; stop option parsing
              (let ((rest (subseq args (1+ i))))
                (when (and rest (null file))
                  (setf file (first rest)))
                (return)))
             ((or (string= a "--help") (string= a "-h"))
              (setf help t))
             ((or (string= a "--version") (string= a "-V"))
              (setf version t))
             ((string= a "--batch")
              (setf batch t))
             ((string= a "--no-elisp")
              (setf no-elisp t))
             ((string= a "-Q")
              (setf quick t no-init t))
             ((string= a "-q")
              (setf no-init t))
             ((or (string= a "--startup-level")
                  (string= a "--startup-limit")
                  (string= a "--eval"))
              (let ((v (take-next i)))
                (cond
                 ((string= a "--startup-level")
                  (setf startup-level v))
                 ((string= a "--startup-limit")
                  (setf startup-limit (parse-int v a)))
                 ((string= a "--eval")
                  (push v eval-strings))))
              (incf i))
             ((%arg-value/equals (list a) "--startup-level=")
              (setf startup-level (subseq a (length "--startup-level="))))
             ((%arg-value/equals (list a) "--startup-limit=")
              (setf startup-limit (parse-int (subseq a (length "--startup-limit=")) a)))
             ((%arg-value/equals (list a) "--eval=")
              (push (subseq a (length "--eval=")) eval-strings))
             ((and (stringp a) (> (length a) 0) (char= (char a 0) #\-))
              (push a unknown))
             ((and (stringp a) (null file))
              (setf file a))
             (t nil)))
          (incf i))))
    (list :batch batch
          :help help
          :version version
          :no-elisp no-elisp
          :quick quick
          :no-init no-init
          :startup-level startup-level
          :startup-limit startup-limit
          :eval-strings (nreverse eval-strings)
          :file file
          :unknown-flags (nreverse unknown))))

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
  ;; The progress dashboard checks keybindings by running the clemacs executable
  ;; in `--batch` mode with `--startup-level tty-editor`.  In that mode, we
  ;; don't run the TTY loop, so the usual `clemacs-tty-setup' keybinding
  ;; "ensure" logic would not run.  Apply it here so tty-editor's keybindings
  ;; are Emacs-shaped even in batch.
  (when (and (stringp level) (string= level "tty-editor") (cl:fboundp 'elisp::clemacs-tty-setup))
    (ignore-errors (elisp::clemacs-tty-setup :path nil)))
  0)

(defun %find-user-init-file ()
  "Return a pathname for the user's init file, or NIL if none exists."
  (let* ((override (uiop:getenv "CLEMACS_INIT_FILE"))
         (home (uiop:getenv "HOME"))
         (xdg (uiop:getenv "XDG_CONFIG_HOME"))
         (candidates
          (remove
           nil
           (list
            (and override (not (string= override "")) (pathname override))
            (and home (not (string= home ""))
                 (merge-pathnames #p".emacs" (uiop:ensure-directory-pathname home)))
            (and home (not (string= home ""))
                 (merge-pathnames #p".emacs.d/init.el" (uiop:ensure-directory-pathname home)))
            (and xdg (not (string= xdg ""))
                 (merge-pathnames #p"emacs/init.el" (uiop:ensure-directory-pathname xdg))))))
         (existing (find-if #'probe-file candidates)))
    existing))

(defun %maybe-load-user-init (&key (stream *standard-output*) (mode :interactive))
  (let ((init (%find-user-init-file)))
    (when (null init)
      (return-from %maybe-load-user-init 0))
    (handler-case
        (progn
          ;; Keep noise low by default; allow opt-in visibility.
          (let ((dbg (uiop:getenv "CLEMACS_DEBUG_INIT")))
            (when (and dbg (not (string= dbg "")))
              (format stream "[clemacs] loading init: ~A~%" init)
              (finish-output stream)))
          (elisp:load-elisp-file init)
          0)
      (error (e)
        (format *error-output* "[clemacs] init load failed: ~A~%" e)
        (finish-output *error-output*)
        (if (eq mode :batch) 1 0)))))

(defun emacs-main (&key (stream *standard-output*))
  "Entry point for the SBCL-hosted `emacs` binary (clemacs).

This is still bring-up quality: it provides a minimal TTY editor loop
and a few batch-friendly flags."
  (let* ((args (%argv))
         (parsed (%parse-argv args)))
    (when (getf parsed :parse-error)
      (return-from emacs-main
        (%usage :stream stream :exit-code 2 :error (getf parsed :parse-error))))
    (let* ((batch (and (getf parsed :batch) t))
           (help (and (getf parsed :help) t))
           (version (and (getf parsed :version) t))
           (no-elisp (and (getf parsed :no-elisp) t))
           (no-init (and (getf parsed :no-init) t))
           (level (or (getf parsed :startup-level)
                      (if batch "smoke" "tty-editor")))
           (limit (getf parsed :startup-limit))
           (eval-strings (or (getf parsed :eval-strings) nil))
           (path (getf parsed :file))
           (unknown (or (getf parsed :unknown-flags) nil)))
      (when unknown
        (return-from emacs-main
          (%usage :stream stream :exit-code 2
                  :error (format nil "unsupported flags: ~{~A~^ ~}" unknown))))
      (cond
       (version
      (format stream "clemacs (SBCL-hosted)~%")
      (format stream "substrate: ~A (~A)~%" (substrate-version) (substrate-platform))
      (finish-output stream)
      0)
       (help
        (%usage :stream stream :exit-code 0))
       (batch
        (setf elisp::noninteractive t)
        (unless no-elisp
          (let ((rc (%maybe-load-startup-elisp :level level :limit limit :stream stream)))
            (when (not (zerop rc))
              (return-from emacs-main rc))))
        (unless no-init
          (let ((rc (%maybe-load-user-init :stream stream :mode :batch)))
            (when (not (zerop rc))
              (return-from emacs-main rc))))
        (handler-case
            (progn
              (dolist (s eval-strings)
                (%batch-eval-string s :stream stream))
              0)
          (error (e)
            (format *error-output* "[clemacs] --eval failed: ~A~%" e)
            (finish-output *error-output*)
            1)))
       (t
        (setf elisp::noninteractive nil)
        (unless no-elisp
          (let ((rc (%maybe-load-startup-elisp :level level :limit limit :stream stream)))
            (when (not (zerop rc))
              (return-from emacs-main rc))))
        (unless no-init
          (ignore-errors (%maybe-load-user-init :stream stream :mode :interactive)))
        (tty-main :path path))))))
