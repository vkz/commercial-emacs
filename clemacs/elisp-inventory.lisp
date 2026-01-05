(in-package #:elisp)

(defstruct elisp-inventory-entry
  kind
  lisp-name
  c-name
  source-path
  source-line)

(cl:defvar *elisp-inventory-cache* nil)
(cl:defvar *elisp-inventory-tsv* nil)

(cl:defun %parent-directory (dir)
  (let* ((dir (uiop:ensure-directory-pathname dir))
         (parts (pathname-directory dir)))
    (when (and (consp parts) (>= (length parts) 2))
      (make-pathname :directory (subseq parts 0 (1- (length parts)))
                     :defaults dir))))

(cl:defun %find-project-file-upwards (start relative &key (max-hops 10))
  (loop with dir = (uiop:ensure-directory-pathname start)
        for hop from 0 below max-hops
        for candidate = (merge-pathnames relative dir)
        when (probe-file candidate) do (return candidate)
        do (setf dir (%parent-directory dir))
        while dir))

(cl:defun %ensure-elisp-inventory-loaded (&key (start-dir *default-pathname-defaults*))
  (when (and *elisp-inventory-cache*
             *elisp-inventory-tsv*
             (probe-file *elisp-inventory-tsv*))
    (return-from %ensure-elisp-inventory-loaded *elisp-inventory-cache*))

  (let ((tsv (%find-project-file-upwards start-dir #p"inventory/c-elisp.tsv")))
    (unless tsv
      (setf *elisp-inventory-cache* nil
            *elisp-inventory-tsv* nil)
      (return-from %ensure-elisp-inventory-loaded nil))

    (setf *elisp-inventory-tsv* tsv)
    (let ((cache (make-hash-table :test 'cl:equal)))
      (with-open-file (in tsv :external-format :utf-8)
        (let ((header (read-line in nil nil)))
          (declare (cl:ignore header))
          (loop for line = (read-line in nil nil)
                while line do
                  (when (and (> (length line) 0)
                             (not (char= (char line 0) #\#)))
                    (let* ((cols (uiop:split-string line :separator '(#\Tab)))
                           (kind (nth 0 cols))
                           (lisp-name (nth 1 cols))
                           (c-name (nth 2 cols))
                           (source-path (nth 3 cols))
                           (source-line (nth 4 cols)))
                      (when lisp-name
                        (setf (gethash (string-downcase lisp-name) cache)
                              (make-elisp-inventory-entry
                               :kind kind
                               :lisp-name lisp-name
                               :c-name c-name
                               :source-path source-path
                               :source-line source-line))))))))
      (setf *elisp-inventory-cache* cache)
      cache)))

(cl:defun inventory-lookup (name &key (start-dir *default-pathname-defaults*))
  (let ((cache (%ensure-elisp-inventory-loaded :start-dir start-dir)))
    (when cache
      (let* ((name
               (etypecase name
                 (string name)
                 (unibyte-string (%elisp-string->cl-string name))
                 (symbol (%elisp-string->cl-string (symbol-name name))))))
        (gethash (string-downcase name) cache)))))

(cl:defun inventory-entry-string (entry)
  (when entry
    (cl:format nil "~A ~A (~A) @ ~A:~A"
               (elisp-inventory-entry-kind entry)
               (elisp-inventory-entry-lisp-name entry)
               (elisp-inventory-entry-c-name entry)
               (elisp-inventory-entry-source-path entry)
               (elisp-inventory-entry-source-line entry))))

(cl:defun inventory-entry-for-condition (condition &key (start-dir *default-pathname-defaults*))
  (labels ((lookup-symbol (sym)
             (when (symbolp sym)
               (inventory-entry-string
                (inventory-lookup (symbol-name sym) :start-dir start-dir)))))
    (cond
     ((typep condition 'undefined-function)
      (lookup-symbol (ignore-errors (cell-error-name condition))))
     ((typep condition 'unbound-variable)
      (lookup-symbol (ignore-errors (cell-error-name condition))))
     (t nil))))
