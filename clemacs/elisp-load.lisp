(in-package #:elisp)

(define-condition elisp-load-error (error)
  ((path :initarg :path :reader elisp-load-error-path)
   (form-index :initarg :form-index :reader elisp-load-error-form-index)
   (form :initarg :form :reader elisp-load-error-form)
   (cause :initarg :cause :reader elisp-load-error-cause)
   (inventory-entry :initarg :inventory-entry :reader elisp-load-error-inventory-entry))
  (:report (lambda (c s)
             (format s "ELisp load error in ~A (form ~D):~%  ~S~%~A~@[~%Inventory: ~A~]"
                     (elisp-load-error-path c)
                     (elisp-load-error-form-index c)
                     (elisp-load-error-form c)
                     (elisp-load-error-cause c)
                     (elisp-load-error-inventory-entry c)))))

(cl:defun %read-manifest-lines (manifest)
  (let ((out nil))
    (with-open-file (in manifest :external-format :utf-8)
      (loop for line = (read-line in nil nil)
            while line do
              (let ((line (string-trim '(#\Space #\Tab #\Return #\Newline) line)))
                (when (and (> (length line) 0)
                           (not (char= (char line 0) #\#)))
                  (push line out)))))
    (nreverse out)))

(cl:defun %read-skip-lines (skip-file)
  (let ((out (make-hash-table :test 'cl:equal)))
    (when (and skip-file (probe-file skip-file))
      (dolist (line (%read-manifest-lines skip-file))
        (setf (gethash line out) t)))
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
    (error "ELISP:LOAD-ELISP-MANIFEST requires :manifest"))
  (let* ((project-root (uiop:ensure-directory-pathname project-root))
         (manifest (merge-pathnames manifest project-root))
         (skip-file (and skip-file (merge-pathnames skip-file project-root)))
         (ported-root (merge-pathnames ported-root project-root))
         (skips (%read-skip-lines skip-file))
         (loaded 0))
    (dolist (line (%read-manifest-lines manifest))
      (when (and limit (>= loaded limit))
        (return))
      (cond
       ((gethash line skips)
        (format t "[clemacs:load] skip ~A~%" line))
       (t
        (let* ((src-path (merge-pathnames line project-root))
               (ported-path (merge-pathnames line ported-root))
               (path (if (probe-file ported-path) ported-path src-path)))
          (load-elisp-file path :max-forms max-forms)
          (incf loaded)))))
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
