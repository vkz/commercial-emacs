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

(cl:defun file-size-human-readable (file-size &optional flavor space unit)
  "Bring-up subset of ELisp `file-size-human-readable'."
  (unless (numberp file-size)
    (error "ELISP:FILE-SIZE-HUMAN-READABLE expects a number, got: ~S" file-size))
  (when (and flavor (not (symbolp flavor)))
    (error "ELISP:FILE-SIZE-HUMAN-READABLE bad FLAVOR: ~S" flavor))
  (when (and space (not (stringp space)))
    (error "ELISP:FILE-SIZE-HUMAN-READABLE bad SPACE: ~S" space))
  (when (and unit (not (stringp unit)))
    (error "ELISP:FILE-SIZE-HUMAN-READABLE bad UNIT: ~S" unit))
  (let* ((power (if (or (null flavor) (eq flavor 'iec)) 1024.0d0 1000.0d0))
         (prefixes '("" "k" "M" "G" "T" "P" "E" "Z" "Y" "R" "Q"))
         (size (cl:coerce file-size 'double-float)))
    (loop while (and (>= size power) (consp (cdr prefixes))) do
      (setf size (/ size power)
            prefixes (cdr prefixes)))
    (let* ((prefix (car prefixes))
           (unit* (or unit (and (eq flavor 'iec) "B") ""))
           (prefixed-unit
             (if (eq flavor 'iec)
                 (concatenate 'cl:string
                              (if (string= prefix "k") "K" prefix)
                              (if (string= prefix "") "" "i")
                              unit*)
                 (concatenate 'cl:string prefix unit*)))
           (need-unit (not (string= prefixed-unit "")))
           (sep (if need-unit (or space "") ""))
           (one-decimal
             (and (< size 10.0d0)
                  (>= (mod size 1.0d0) 0.05d0)
                  (< (mod size 1.0d0) 0.95d0)))
           (num
             (if one-decimal
                 (cl:format nil "~,1F" size)
                 (let* ((s (cl:format nil "~,0F" size))
                        (n (length s)))
                   ;; `~F' prints a trailing '.' even with 0 decimals; strip it.
                   (if (and (> n 0) (char= (char s (1- n)) #\.))
                       (subseq s 0 (1- n))
                       s)))))
      (concatenate 'cl:string num sep prefixed-unit))))

(cl:defun ls-lisp-time-index (switches)
  "Bring-up stub for ELisp `ls-lisp-time-index'."
  (cond
   ((memq ?c switches) 6)
   ((memq ?t switches) 5)
   ((memq ?u switches) 4)))

(cl:defun ls-lisp-extension (filename)
  "Bring-up stub for ELisp `ls-lisp-extension'."
  (let* ((s (%elisp-string->cl-string filename))
         (nul (string (code-char 0)))
         (len (length s)))
    (when (zerop len)
      (return-from ls-lisp-extension (concatenate 'cl:string nul nul nul)))
    (labels ((no-ext () (concatenate 'cl:string nul nul))
             (null-ext () nul))
      (let ((i (1- len)))
        (if (char= (char s i) #\.)
            ;; Null extension.
            (concatenate 'cl:string (null-ext) nul s)
            (progn
              ;; Find final '.'.
              (loop while (and (>= i 0) (not (char= (char s i) #\.))) do
                (decf i))
              (let ((ext
                      (cond
                       ((minusp i) (no-ext))
                       ;; Regular extension.
                       ((not (char= (char s (1+ i)) #\~))
                        (subseq s (1+ i)))
                       ;; Version extension: ignore trailing "~" part.
                       (t
                        (let ((end i))
                          (decf i)
                          (loop while (and (>= i 0) (not (char= (char s i) #\.))) do
                            (decf i))
                          (if (minusp i)
                              (no-ext)
                              (subseq s (1+ i) end)))))))
                (concatenate 'cl:string ext nul s))))))))

(cl:defun ls-lisp-format-file-size (file-size human-readable)
  "Bring-up stub for ELisp `ls-lisp-format-file-size'."
  (if (not human-readable)
      (cl:format nil " ~A" file-size)
      (cl:format nil " ~7A" (file-size-human-readable file-size))))

(cl:defun %file-attrs--seconds->time (sec)
  (let ((hi (floor sec 65536))
        (lo (mod sec 65536)))
    (list hi lo 0 0)))

(cl:defun %file-attrs--mode-type (mode)
  (let ((type (logand mode #o170000)))
    (cond
     ((= type #o040000) :directory)
     ((= type #o120000) :symlink)
     ((= type #o0100000) :regular)
     (t :other))))

(cl:defun %file-attrs--modes-string (mode)
  (labels ((mode-bit (mask ch)
             (if (not (zerop (logand mode mask))) ch #\-)))
    (let ((type-ch
            (case (%file-attrs--mode-type mode)
              (:directory #\d)
              (:symlink #\l)
              (:regular #\-)
              (t #\?))))
      (coerce
       (list type-ch
             (mode-bit #o400 #\r) (mode-bit #o200 #\w) (mode-bit #o100 #\x)
             (mode-bit #o040 #\r) (mode-bit #o020 #\w) (mode-bit #o010 #\x)
             (mode-bit #o004 #\r) (mode-bit #o002 #\w) (mode-bit #o001 #\x))
       'cl:string))))

(cl:defun file-attributes (filename &optional id-format)
  "Bring-up subset of the C primitive `file-attributes'."
  (declare (cl:ignore id-format))
  (let* ((path (%file-name->cl-string filename))
         (path* (%expand-tilde-file-name path)))
    (multiple-value-bind (ok _errno ino mode nlink uid gid rdev size atime mtime ctime _blksize _blocks)
        (sb-unix:unix-lstat path*)
      (declare (cl:ignore _errno rdev _blksize _blocks))
      (unless ok
        (return-from file-attributes nil))
      (let* ((type (%file-attrs--mode-type mode))
             (link-target
               (when (eq type :symlink)
                 (multiple-value-bind (target _errno2) (sb-unix:unix-readlink path*)
                   (declare (cl:ignore _errno2))
                   target)))
             (type-field
               (cond
                ((eq type :directory) t)
                ((eq type :symlink) (and link-target (string-to-unibyte link-target)))
                (t nil))))
        (list type-field
              nlink
              uid
              gid
              (%file-attrs--seconds->time atime)
              (%file-attrs--seconds->time mtime)
              (%file-attrs--seconds->time ctime)
              size
              (string-to-unibyte (%file-attrs--modes-string mode))
              nil
              ino
              0)))))

(cl:defun %directory-files--basename (pathname)
  (let* ((p (uiop:ensure-pathname pathname :want-pathname t :want-absolute t))
         (name (pathname-name p))
         (type (pathname-type p))
         (dir (pathname-directory p)))
    (cond
     (name
      (if type
          (concatenate 'cl:string name "." type)
          name))
     ((and (consp dir) (stringp (car (last dir))))
      (car (last dir)))
     (t
      ""))))

(cl:defun %directory-files--namestring (pathname)
  (let* ((s (namestring pathname))
         (len (length s)))
    (cond
     ((and (> len 1) (char= (char s (1- len)) #\/))
      (subseq s 0 (1- len)))
     (t s))))

(cl:defun directory-files (directory &optional full match nosort count)
  "Bring-up subset of the C primitive `directory-files'."
  (let* ((dir (%file-name->cl-string directory))
         (dir* (uiop:ensure-directory-pathname (%expand-tilde-file-name dir)))
         (pattern (merge-pathnames "*" dir*))
         (paths (ignore-errors (directory pattern)))
         (names (append (list "." "..")
                        (loop for p in paths
                              for base = (%directory-files--basename p)
                              unless (or (string= base ".") (string= base ".."))
                                collect base))))
    (when match
      (setf names
            (loop for n in names
                  when (string-match-p match (string-to-unibyte n))
                    collect n)))
    (unless nosort
      (setf names (sort names #'string<)))
    (when (and (integerp count) (plusp count) (> (length names) count))
      (setf names (subseq names 0 count)))
    (let ((dir-prefix (file-name-as-directory (namestring dir*))))
      (loop for n in names collect
        (string-to-unibyte
         (cond
          (full (concatenate 'cl:string dir-prefix n))
          (t n)))))))

(cl:defun directory-files-and-attributes (directory &optional full match nosort id-format count)
  "Bring-up subset of ELisp `directory-files-and-attributes'."
  (let* ((names (directory-files directory full match nosort count))
         (dir-prefix (file-name-as-directory (%file-name->cl-string directory))))
    (loop for n in names collect
      (let* ((nstr (%file-name->cl-string n))
             (path
               (cond
                (full nstr)
                (t (concatenate 'cl:string dir-prefix nstr)))))
        (cons n (file-attributes (string-to-unibyte path) id-format))))))

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
