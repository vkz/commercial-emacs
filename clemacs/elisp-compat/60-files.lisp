(in-package #:elisp)

;; ---------------------------------------------------------------------------
;; Minimal filesystem surface (enough for upstream ERT-x temp file tests)
;; ---------------------------------------------------------------------------

(cl:defun %file-name->cl-string (x)
  (cond
   ((unibyte-string-p x) (%elisp-string->cl-string x))
   ((cl:stringp x) x)
   (t (error "ELISP: expected file name string, got: ~S" x))))

(cl:defun file-name-as-directory (file)
  "Bring-up subset of ELisp `file-name-as-directory'."
  (let* ((s (%file-name->cl-string file))
         (len (length s)))
    (cond
     ((= len 0) s)
     ((or (char= (char s (1- len)) #\/)
          (char= (char s (1- len)) #\\))
      s)
     (t
      (concatenate 'cl:string s "/")))))

(cl:defun file-exists-p (filename)
  "Bring-up subset of ELisp `file-exists-p'."
  (let ((s (%file-name->cl-string filename)))
    (and (probe-file s) t)))

(cl:defun file-directory-p (filename)
  "Bring-up subset of ELisp `file-directory-p'."
  (let* ((s (%file-name->cl-string filename))
         (p (ignore-errors (uiop:ensure-directory-pathname s))))
    (and p (uiop:directory-exists-p p) t)))

(cl:defun file-regular-p (filename)
  "Bring-up subset of ELisp `file-regular-p'."
  (and (file-exists-p filename)
       (not (file-directory-p filename))
       t))

(cl:defun delete-directory (dir &optional recursive _trash)
  "Bring-up subset of ELisp `delete-directory'."
  (declare (cl:ignore _trash))
  (let* ((s (%file-name->cl-string dir))
         (p (uiop:ensure-directory-pathname s)))
    (cond
     (recursive
      (uiop:delete-directory-tree p :validate t)
      t)
     (t
      ;; Best-effort empty dir delete.
      (uiop:delete-empty-directory p)
      t))))

(cl:defun make-temp-file (prefix &optional dir-flag suffix text)
  "Bring-up subset of ELisp `make-temp-file'."
  (when (and dir-flag text)
    (error "ELISP:MAKE-TEMP-FILE cannot accept TEXT for directories"))
  (let* ((prefix* (%file-name->cl-string prefix))
         (suffix* (and suffix (%file-name->cl-string suffix)))
         (prefix-slash (position #\/ prefix* :from-end t))
         (base-dir
           (cond
            (prefix-slash
             (file-name-as-directory (subseq prefix* 0 (1+ prefix-slash))))
            ((and (boundp 'temporary-file-directory)
                  temporary-file-directory)
             (file-name-as-directory temporary-file-directory))
            (t
             (namestring (uiop:temporary-directory)))))
         (name-prefix
           (if prefix-slash
               (subseq prefix* (1+ prefix-slash))
               prefix*))
         (base-dir (file-name-as-directory base-dir))
         (base-path (pathname base-dir)))
    (loop for _attempt from 0 below 500
          for rand = (cl:format nil "~8,'0x" (random #x100000000))
          for leaf = (concatenate 'cl:string name-prefix rand (or suffix* ""))
          for p = (merge-pathnames leaf base-path)
          unless (probe-file p) do
            (if dir-flag
                (let ((dirp (uiop:ensure-directory-pathname p)))
                  (ensure-directories-exist (merge-pathnames "dummy" dirp))
                  (return (namestring dirp)))
                (progn
                  (with-open-file (out p
                                       :direction :output
                                       :if-does-not-exist :create
                                       :if-exists :error
                                       :external-format :utf-8)
                    (when text
                      (write-string (%file-name->cl-string text) out)))
                  (return (namestring p))))
          finally
            (error "ELISP:MAKE-TEMP-FILE failed to find a unique name"))))

(cl:defun find-file-noselect (filename &optional _nowarn _rawfile _wildcards)
  "Bring-up subset of ELisp `find-file-noselect'."
  (declare (cl:ignore _nowarn _rawfile _wildcards))
  (let* ((path (%file-name->cl-string filename))
         (buf (get-buffer-create (string-to-unibyte path)))
         (txt (uiop:read-file-string path :external-format :utf-8)))
    (setf (elisp-buffer-text buf) txt
          (elisp-buffer-point buf) 1
          (elisp-buffer-modified-p buf) nil)
    buf))

(cl:defun find-file-literally (filename &optional _nowarn)
  "Bring-up subset of ELisp `find-file-literally'."
  (declare (cl:ignore _nowarn))
  (find-file-noselect filename))
