(in-package #:elisp)

;; ---------------------------------------------------------------------------
;; Minimal filesystem surface (enough for upstream ERT-x temp file tests)
;; ---------------------------------------------------------------------------

(cl:defvar interpreter-mode-alist nil)
(cl:defvar major-mode-remap-defaults nil)
(cl:defvar file-name-handler-alist nil)

(cl:defun find-file-name-handler (_filename _operation)
  "Bring-up stub for the C primitive `find-file-name-handler'."
  (declare (cl:ignore _filename _operation))
  nil)

(cl:defun file-name-case-insensitive-p (_filename)
  "Bring-up stub for the C primitive `file-name-case-insensitive-p'."
  (declare (cl:ignore _filename))
  nil)

(cl:defun %initial-exec-path ()
  (let ((path (uiop:getenv "PATH")))
    (cond
     ((and (cl:stringp path) (cl:> (length path) 0))
      (uiop:split-string path :separator ":"))
     (t nil))))

(cl:defvar exec-path (%initial-exec-path))
(cl:defvar exec-suffixes (list ""))

(cl:defun file-name-quote (name &optional _top)
  "Bring-up stub for ELisp `file-name-quote'.

For now, return NAME unchanged.  clemacs does not yet implement file name
handlers or Tramp-style remote file parsing."
  (declare (cl:ignore _top))
  name)

(cl:defun get-load-suffixes ()
  "Bring-up subset of ELisp `get-load-suffixes'.

This is a C primitive in Emacs (`Fget_load_suffixes`).  For clemacs bring-up,
return either the user-configured `load-suffixes' (when bound) or a minimal
TTY-relevant default."
  (let ((v (and (boundp 'load-suffixes) (symbol-value 'load-suffixes))))
    (cond
     ((consp v) v)
     (t
      (list (string-to-unibyte ".elc")
            (string-to-unibyte ".el"))))))

(cl:defun %locate-file-minimal (filename path &optional suffixes predicate)
  (let* ((name (%file-name->cl-string filename))
         (dirs (if (consp path) path (list path)))
         (suffixes* (or suffixes (list (string-to-unibyte ""))))
         (suffixes-cl (mapcar (lambda (s)
                                (if s (%file-name->cl-string s) ""))
                              suffixes*))
         (default-dir
           (and (boundp 'default-directory)
                (%file-name->cl-string (symbol-value 'default-directory))))
         (pred
           (cond
            ((null predicate) nil)
            ((functionp predicate) predicate)
            (t nil))))
    (dolist (dir dirs nil)
      (let* ((dirstr
               (cond
                ((null dir) default-dir)
                (t (%file-name->cl-string dir))))
             (prefix
               (cond
                ((or (null dirstr) (= (length dirstr) 0)) "")
                (t (file-name-as-directory dirstr))))
             (base (concatenate 'cl:string prefix name)))
        (dolist (suf suffixes-cl)
          (let* ((cand (concatenate 'cl:string base suf))
                 (p (probe-file cand)))
            (when (and p (or (null pred) (funcall pred cand)))
                      (return-from %locate-file-minimal (string-to-unibyte (namestring p))))))))))

(cl:defun locate-file (filename path &optional suffixes predicate)
  "Bring-up subset of ELisp `locate-file'.

This is normally defined in `lisp/files.el` and used by `locate-library` in
`lisp/subr.el`.  For bring-up, implement a minimal search over PATH and
SUFFIXES, returning the first probeable match as an absolute file name string
or nil."
  (%locate-file-minimal filename path suffixes predicate))

(cl:defun locate-file-internal (filename path &optional suffixes predicate)
  "Bring-up subset of the C primitive `locate-file-internal'."
  (%locate-file-minimal filename path suffixes predicate))

(cl:defun load (file &optional noerror _nomessage nosuffix _must-suffix)
  "Bring-up subset of ELisp `load'.

This shadows `cl:load' inside the ELISP package.  For bring-up, support loading
plain `.el' files by searching `load-path' and evaluating the file via
`load-elisp-file'."
  (declare (cl:ignore _nomessage _must-suffix))
  (let* ((filestr (%file-name->cl-string file))
         (direct (probe-file filestr))
         (load-path*
           (and (boundp 'load-path) (symbol-value 'load-path)))
         (found
           (or direct
               (and load-path*
                    (let* ((suffixes
                             (cond
                              (nosuffix (list (string-to-unibyte "")))
                              (t (list (string-to-unibyte ""))))))
                      (let ((s (locate-file file load-path* suffixes)))
                        (and s (probe-file (%file-name->cl-string s)))))))))
    (cond
     (found
      (load-elisp-file found :package nil)
      t)
     (noerror
      nil)
     (t
      (error "ELISP:LOAD could not find: ~S" file)))))

(cl:defun %file-name->cl-string (x)
  (cond
   ((unibyte-string-p x) (%elisp-string->cl-string x))
   ((cl:stringp x) x)
   (t (error "ELISP: expected file name string, got: ~S" x))))

(cl:defun %expand-tilde-file-name (s)
  (cond
   ((and (cl:> (length s) 0) (cl:char= (char s 0) #\~))
    (let* ((slash (position #\/ s))
           (rest (if slash (subseq s slash) "")))
      ;; Bring-up subset: treat "~" and "~/" as current user's home; treat
      ;; "~user" as "~" for now.
      (namestring (merge-pathnames rest (user-homedir-pathname)))))
   (t s)))

(cl:defun expand-file-name (name &optional default-directory)
  "Bring-up subset of the C primitive `expand-file-name'."
  (let* ((name-str (%expand-tilde-file-name (%file-name->cl-string name)))
         (base-str
           (cond
            (default-directory (%file-name->cl-string default-directory))
            ((and (boundp 'default-directory) (stringp (symbol-value 'default-directory)))
             (%file-name->cl-string (symbol-value 'default-directory)))
            (t (namestring (uiop:getcwd))))))
    (cond
     ;; Absolute path.
     ((and (cl:> (length name-str) 0) (cl:char= (char name-str 0) #\/))
      name-str)
     (t
      (let* ((base (uiop:ensure-directory-pathname base-str))
             (p (uiop:merge-pathnames* name-str base)))
        (namestring p))))))

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

(cl:defun file-readable-p (filename)
  "Bring-up subset of the C primitive `file-readable-p'."
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
