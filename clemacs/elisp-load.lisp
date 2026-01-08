(in-package #:elisp)

(define-condition elisp-load-error (cl:error)
  ((path :initarg :path :reader elisp-load-error-path)
   (form-index :initarg :form-index :reader elisp-load-error-form-index)
   (form :initarg :form :reader elisp-load-error-form)
   (cause :initarg :cause :reader elisp-load-error-cause)
   (inventory-entry :initarg :inventory-entry :reader elisp-load-error-inventory-entry))
  (:report (lambda (c s)
             (cl:format s "ELisp load error in ~A (form ~D):~%  ~S~%~A~@[~%Inventory: ~A~]"
                        (elisp-load-error-path c)
                        (elisp-load-error-form-index c)
                        (elisp-load-error-form c)
                        (elisp-load-error-cause c)
                        (elisp-load-error-inventory-entry c)))))

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
         (loaded 0))
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
    (dolist (line (%read-noncomment-lines manifest))
      (when (and limit (>= loaded limit))
        (return))
      (multiple-value-bind (rel-path entry-max-forms) (%parse-manifest-entry line)
        (cond
         ((gethash rel-path skips)
          (cl:format t "[clemacs:load] skip ~A~%" rel-path))
         (t
          (let* ((src-path (merge-pathnames rel-path project-root))
                 (ported-path (merge-pathnames rel-path ported-root))
                 (path (if (probe-file ported-path) ported-path src-path))
                 (eff-max-forms
                   (cond
                    ((eq entry-max-forms :no-limit) nil)
                    ((eq entry-max-forms :inherit) max-forms)
                    (t (or entry-max-forms max-forms)))))
            (load-elisp-file path :max-forms eff-max-forms)
            (incf loaded))))))
    0))

(cl:defun load-bootstrap-set (&key (project-root (uiop:getcwd))
                                   (manifest #p"clemacs/contract/bootstrap.files")
                                   (limit nil)
                                   (max-forms nil))
  "Backwards-compatible wrapper for the initial ELisp bootstrap manifest."
  (load-elisp-manifest :project-root project-root
                       :manifest manifest
                       :limit limit
                       :max-forms max-forms))
