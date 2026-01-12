(in-package #:elisp)

;; ---------------------------------------------------------------------------
;; Minimal filesystem surface (enough for upstream ERT-x temp file tests)
;; ---------------------------------------------------------------------------

(cl:defvar interpreter-mode-alist nil)
(cl:defvar major-mode-remap-defaults nil)
(cl:defvar file-name-handler-alist nil)

(cl:defvar uniquify-trailing-separator-p nil)
(cl:defvar uniquify-buffer-name-style nil)
(cl:defvar uniquify-separator "\\")

(cl:defvar auto-save-visited-file-name nil)
(cl:defvar buffer-auto-save-file-name nil)
(cl:defvar buffer-file-coding-system nil)
(cl:defvar last-coding-system-used nil)
(cl:defvar buffer-file-coding-system-explicit nil)

(cl:defun secure-hash-algorithms ()
  "Bring-up subset of the C primitive `secure-hash-algorithms'."
  (cl:list 'md5 'sha1 'sha224 'sha256 'sha384 'sha512))

(cl:defun %initial-temporary-file-directory ()
  (let* ((env (or (uiop:getenv "TMPDIR")
                  (uiop:getenv "TMP")
                  (uiop:getenv "TEMP")))
         (base (cond
                ((and (cl:stringp env) (cl:> (length env) 0)) env)
                (t (namestring (uiop:temporary-directory)))))
         (out (if (and (cl:> (length base) 0)
                       (cl:char= (cl:aref base (cl:1- (length base))) #\/))
                  base
                  (cl:concatenate 'cl:string base "/"))))
    ;; Return a CL string so this can be used safely during early system load
    ;; (before the ELisp arithmetic predicates used by `string-to-unibyte` exist).
    out))

(cl:defvar temporary-file-directory nil)

;; In upstream Emacs, `temporary-file-directory' is initialized very early (C).
;; In clemacs bring-up, it can be bound to NIL before `lisp/files.el' runs; give
;; it a stable default so `find-file' and backup logic don't explode.
(unless (and (stringp temporary-file-directory)
             (cl:> (length temporary-file-directory) 0))
  (setf (cl:symbol-value 'temporary-file-directory)
        (%initial-temporary-file-directory)))

(cl:defun vc-before-save ()
  "Bring-up stub for `vc-before-save' (avoid VC hooks in the TTY slice)."
  nil)

(cl:defun vc-after-save ()
  "Bring-up stub for `vc-after-save' (avoid VC hooks in the TTY slice)."
  nil)

(cl:defun uniquify--create-file-buffer-advice (&rest _args)
  "Bring-up stub used by `create-file-buffer' (see `lisp/files.el')."
  (declare (cl:ignore _args))
  nil)

(cl:defun next-read-file-uses-dialog-p ()
  "TTY-only stub for `next-read-file-uses-dialog-p'."
  nil)

(cl:defun recent-auto-save-p ()
  "Bring-up stub for the C primitive `recent-auto-save-p'."
  nil)

(cl:defun find-file-long-lines-p (_filename)
  "Bring-up stub for the C primitive `find-file-long-lines-p'.

Return nil so `find-file' does not prompt about very long lines yet."
  (declare (cl:ignore _filename))
  nil)

(cl:defun find-file-name-handler (_filename _operation)
  "Bring-up stub for the C primitive `find-file-name-handler'."
  (declare (cl:ignore _filename _operation))
  nil)

(cl:defun get-file-buffer (filename)
  "Bring-up subset of the C primitive `get-file-buffer'.

Return a live buffer visiting FILENAME, or nil."
  (unless (stringp filename)
    (error "ELISP:GET-FILE-BUFFER expected string, got: ~S" filename))
  (let* ((target (expand-file-name filename))
         (target* (%file-name->cl-string target))
         (found nil))
    (dolist (buf (buffer-list))
      (let ((bf (ignore-errors (buffer-file-name buf))))
        (when (and (stringp bf)
                   (cl:string=
                    (%file-name->cl-string (expand-file-name bf))
                    target*))
          (setf found buf)
          (return))))
    found))

(cl:defun get-truename-buffer (filename)
  "Bring-up subset of the C primitive `get-truename-buffer'.

Return a live buffer visiting the true name of FILENAME, or nil."
  (unless (stringp filename)
    (error "ELISP:GET-TRUENAME-BUFFER expected string, got: ~S" filename))
  (let* ((expanded (expand-file-name filename))
         (expanded* (%file-name->cl-string expanded))
         (tru*
           (let* ((p (probe-file expanded*)))
             (when p
               (ignore-errors (namestring (truename p)))))))
    (dolist (buf (buffer-list) nil)
      (let* ((bf (ignore-errors (buffer-file-name buf)))
             (bt (ignore-errors (buffer-local-value 'buffer-file-truename buf))))
        (when (or (and tru* (stringp bt)
                       (cl:string= (%file-name->cl-string bt) tru*))
                  (and (stringp bf)
                       (cl:string=
                        (%file-name->cl-string (expand-file-name bf))
                        expanded*)))
          (return buf))))))

(cl:defun file-name-case-insensitive-p (_filename)
  "Bring-up stub for the C primitive `file-name-case-insensitive-p'."
  (declare (cl:ignore _filename))
  nil)

(cl:defun verify-visited-file-modtime (&optional _buffer)
  "Bring-up stub for the C primitive `verify-visited-file-modtime'.

Return t so `save-buffer' can proceed without modtime tracking yet."
  (declare (cl:ignore _buffer))
  t)

(cl:defun visited-file-modtime ()
  "Bring-up subset of the C primitive `visited-file-modtime'."
  (let ((file (and (boundp 'buffer-file-name) (symbol-value 'buffer-file-name))))
    (cond
     ((not (stringp file)) 0)
     (t
      (let ((attrs (file-attributes file)))
        ;; file-attributes: (TYPE NLINK UID GID ATIME MTIME CTIME ...).
        (or (nth 5 attrs) 0))))))

(cl:defun set-visited-file-modtime (&optional _time)
  "Bring-up subset of the C primitive `set-visited-file-modtime'."
  (declare (cl:ignore _time))
  ;; For now, we do not track per-buffer visited modtime state.  Most callers
  ;; already gate user-visible behavior through `verify-visited-file-modtime'.
  t)

(cl:defun lock-buffer ()
  "Bring-up stub for file locking (no-op)."
  nil)

(cl:defun unlock-buffer ()
  "Bring-up stub for file locking (no-op)."
  nil)

(cl:defun read-file-name (prompt &optional dir default-filename _mustmatch initial _predicate)
  "Bring-up subset of the C primitive `read-file-name' (TTY only).

This does not implement completion.  It prompts for a path and returns an
expanded file name string."
  (declare (cl:ignore _mustmatch _predicate))
  (unless (stringp prompt)
    (error "ELISP:READ-FILE-NAME expected string PROMPT, got: ~S" prompt))
  (let* ((base
           (cond
            ((and dir (stringp dir)) dir)
            ((and (boundp 'default-directory) (stringp (symbol-value 'default-directory)))
             (symbol-value 'default-directory))
            (t nil)))
         (initial*
           (cond
            ;; INITIAL is for pre-populating the minibuffer; DEFAULT-FILENAME is
            ;; only the fallback value when the user enters an empty string.
            ((and initial (stringp initial)) initial)
            (t nil)))
         (input (read-from-minibuffer prompt initial*)))
    (when (and (stringp input)
               (= (length (%file-name->cl-string input)) 0)
               (stringp default-filename))
      (setf input default-filename))
    (cond
     ((null input) nil)
     ((and base (stringp base))
      (string-to-unibyte (expand-file-name input base)))
     (t
      (string-to-unibyte (expand-file-name input))))))

(cl:defun %initial-exec-path ()
  (let ((path (uiop:getenv "PATH")))
    (cond
     ((and (cl:stringp path) (cl:> (length path) 0))
      (uiop:split-string path :separator ":"))
     (t nil))))

(cl:defvar exec-path (%initial-exec-path))
(cl:defvar exec-suffixes (list ""))

(cl:defvar buffer-file-truename nil)

(cl:defun file-symlink-p (filename)
  "Bring-up subset of the C primitive `file-symlink-p'."
  (unless (stringp filename)
    (error "ELISP:FILE-SYMLINK-P expected string, got: ~S" filename))
  #+sbcl
  (handler-case
      (let* ((path (%file-name->cl-string filename))
             (st (sb-posix:lstat path))
             (mode (sb-posix:stat-mode st)))
        (if (sb-posix:s-islnk mode)
            (string-to-unibyte (sb-posix:readlink path))
            nil))
    (sb-posix:syscall-error () nil)
    (cl:error () nil))
  #-sbcl
  nil)

(cl:defun file-acl (_filename)
  "Bring-up stub for the C primitive `file-acl'."
  (declare (cl:ignore _filename))
  nil)

(cl:defun set-file-acl (_filename _acl-string)
  "Bring-up stub for the C primitive `set-file-acl'."
  (declare (cl:ignore _filename _acl-string))
  nil)

(cl:defun file-selinux-context (_filename)
  "Bring-up stub for the C primitive `file-selinux-context'."
  (declare (cl:ignore _filename))
  nil)

(cl:defun set-file-selinux-context (_filename _context)
  "Bring-up stub for the C primitive `set-file-selinux-context'."
  (declare (cl:ignore _filename _context))
  nil)

(cl:defun user-uid ()
  "Bring-up stub for the C primitive `user-uid'."
  0)

(cl:defvar user-login-name nil)

(cl:defun user-login-name (&optional _uid)
  "Bring-up subset of the C primitive `user-login-name'."
  (or user-login-name
      (let ((name (or (uiop:getenv "LOGNAME")
                      (uiop:getenv "USER"))))
        (when name
          (setf user-login-name name))
        name)))

(cl:defvar data-directory
  (let* ((clemacs-dir (uiop:ensure-directory-pathname
                       (asdf:system-source-directory :clemacs)))
         (root (uiop:pathname-parent-directory-pathname clemacs-dir))
         (etc (merge-pathnames #p"etc/" (uiop:ensure-directory-pathname root))))
    (namestring etc)))

(cl:defun %posix-access-ok-p (path mode)
  #+sbcl
  (handler-case
      (progn (sb-posix:access path mode) t)
    (sb-posix:syscall-error () nil)
    (cl:error () nil))
  #-sbcl
  (declare (cl:ignore path mode))
  #-sbcl
  nil)

(cl:defun %file-parent-directory (path)
  (let ((slash (position #\/ path :from-end t)))
    (cond
     ((null slash)
      (cond
       ((and (boundp 'default-directory)
             (stringp (symbol-value 'default-directory)))
        (%file-name->cl-string (symbol-value 'default-directory)))
       (t ".")))
     ((zerop slash) "/")
     (t (subseq path 0 (1+ slash))))))

(cl:defun file-writable-p (filename)
  "Bring-up subset of the C primitive `file-writable-p'."
  (unless (stringp filename)
    (error "ELISP:FILE-WRITABLE-P expected string, got: ~S" filename))
  (let* ((path (%file-name->cl-string filename))
         (existing (probe-file path)))
    (cond
     (existing
      (and (%posix-access-ok-p (namestring existing) sb-posix:w-ok) t))
     (t
      (let ((dir (%file-parent-directory path)))
        (and dir (%posix-access-ok-p dir sb-posix:w-ok) t))))))

(cl:defun file-accessible-directory-p (filename)
  "Bring-up subset of the C primitive `file-accessible-directory-p'."
  (unless (stringp filename)
    (error "ELISP:FILE-ACCESSIBLE-DIRECTORY-P expected string, got: ~S" filename))
  (let* ((path (%file-name->cl-string filename))
         (dir (ignore-errors (uiop:ensure-directory-pathname (pathname path)))))
    (and dir
         (uiop:directory-exists-p dir)
         (%posix-access-ok-p (namestring dir)
                             (logior sb-posix:r-ok sb-posix:x-ok))
         t)))

(cl:defun %posix-current-umask ()
  #+sbcl
  (let ((old (sb-posix:umask 0)))
    (sb-posix:umask old)
    old)
  #-sbcl
  #o022)

(cl:defun default-file-modes ()
  "Bring-up subset of the C primitive `default-file-modes'."
  (let ((umask (%posix-current-umask)))
    (logand #o666 (logand #o777 (lognot umask)))))

(cl:defun set-default-file-modes (modes)
  "Bring-up subset of the C primitive `set-default-file-modes'."
  (unless (integerp modes)
    (error "ELISP:SET-DEFAULT-FILE-MODES expected integer, got: ~S" modes))
  (let* ((old (default-file-modes))
         (m (logand modes #o777))
         (umask (logand #o777 (lognot m))))
    #+sbcl
    (sb-posix:umask umask)
    old))

(cl:defun file-modes (filename)
  "Bring-up subset of the C primitive `file-modes'."
  (unless (stringp filename)
    (error "ELISP:FILE-MODES expected string, got: ~S" filename))
  #+sbcl
  (handler-case
      (let* ((path (%file-name->cl-string filename))
             (st (sb-posix:stat path)))
        (sb-posix:stat-mode st))
    (sb-posix:syscall-error () nil)
    (cl:error () nil))
  #-sbcl
  nil)

(cl:defun set-file-modes (filename mode &optional _flag)
  "Bring-up subset of the C primitive `set-file-modes'."
  (declare (cl:ignore _flag))
  (unless (stringp filename)
    (error "ELISP:SET-FILE-MODES expected string FILENAME, got: ~S" filename))
  (unless (integerp mode)
    (error "ELISP:SET-FILE-MODES expected integer MODE, got: ~S" mode))
  #+sbcl
  (handler-case
      (progn
        (sb-posix:chmod (%file-name->cl-string filename) mode)
        t)
    (sb-posix:syscall-error () nil)
    (cl:error () nil))
  #-sbcl
  nil)

(cl:defun directory-name-p (filename)
  "Bring-up subset of the C primitive `directory-name-p'."
  (unless (stringp filename)
    (error "ELISP:DIRECTORY-NAME-P expected string, got: ~S" filename))
  (let* ((s (%file-name->cl-string filename))
         (n (length s)))
    (and (> n 0)
         (char= (char s (1- n)) #\/)
         t)))

(cl:defun file-name-with-extension (filename extension)
  "Bring-up subset of ELisp `file-name-with-extension'."
  (unless (stringp filename)
    (error "ELISP:FILE-NAME-WITH-EXTENSION expected string FILENAME, got: ~S" filename))
  (unless (stringp extension)
    (error "ELISP:FILE-NAME-WITH-EXTENSION expected string EXTENSION, got: ~S" extension))
  (let* ((base (%file-name->cl-string filename))
         (ext (%elisp-string->cl-string extension))
         (ext* (if (and (> (length ext) 0) (char= (char ext 0) #\.))
                   ext
                   (concatenate 'cl:string "." ext)))
         (dot (position #\. base :from-end t))
         (slash (position #\/ base :from-end t))
         (stem (if (and dot (or (null slash) (> dot slash)))
                   (subseq base 0 dot)
                   base)))
    (string-to-unibyte (concatenate 'cl:string stem ext*))))

(cl:defmacro with-temp-file (file &rest body)
  "Bring-up subset of ELisp `with-temp-file'."
  (let ((f (cl:gensym "FILE-"))
        (v (cl:gensym "VALUE-")))
    `(let ((,f ,file))
       (with-temp-buffer
         (let ((,v (progn ,@body)))
           (write-region (point-min) (point-max) ,f nil)
           ,v)))))

(cl:defun file-name-quote (name &optional _top)
  "Bring-up stub for ELisp `file-name-quote'.

For now, return NAME unchanged.  clemacs does not yet implement file name
handlers or Tramp-style remote file parsing."
  (declare (cl:ignore _top))
  name)

(cl:defun file-name-quoted-p (_name)
  "Bring-up subset of the C primitive `file-name-quoted-p'."
  ;; clemacs does not implement file-name quoting yet; treat names as unquoted.
  nil)

(cl:defun file-relative-name (filename &optional directory)
  "Bring-up subset of ELisp `file-relative-name'."
  (unless (stringp filename)
    (error "ELISP:FILE-RELATIVE-NAME expected string, got: ~S" filename))
  (let* ((file (%file-name->cl-string filename))
         (dir (cond
               ((and directory (stringp directory)) (%file-name->cl-string directory))
               ((and (boundp 'default-directory) (stringp (symbol-value 'default-directory)))
                (%file-name->cl-string (symbol-value 'default-directory)))
               (t nil))))
    (cond
     ((null dir) filename)
     (t
      (handler-case
          (string-to-unibyte
           (enough-namestring (pathname file)
                              (uiop:ensure-directory-pathname (pathname dir))))
        (cl:error () filename))))))

(cl:defmacro with-connection-local-variables (&rest body)
  "Bring-up stub for `with-connection-local-variables'."
  `(progn ,@body))

(cl:defun with-connection-local-variables-1 (body-fun)
  "Bring-up stub for `with-connection-local-variables-1'."
  (funcall body-fun))

(cl:defun get-load-suffixes ()
  "Bring-up subset of ELisp `get-load-suffixes'.

This is a C primitive in Emacs (`Fget_load_suffixes`).  For clemacs bring-up,
return either the user-configured `load-suffixes' (when bound) or a minimal
TTY-relevant default."
  (let ((v (and (boundp 'load-suffixes) (symbol-value 'load-suffixes))))
    (cond
     ((consp v) v)
     (t
      ;; clemacs does not support bytecode (.elc) yet; prefer source.
      (list (string-to-unibyte ".el"))))))

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
         (suffixes
           (cond
            (nosuffix (list (string-to-unibyte "")))
            (t (get-load-suffixes))))
         (found
           (or direct
               (and load-path*
                    (let ((s (locate-file file load-path* suffixes)))
                      (and s (probe-file (%file-name->cl-string s))))))))
    (cond
     (found
      (load-elisp-file found)
      t)
     (noerror
      nil)
     (t
      (error "ELISP:LOAD could not find: ~S" file)))))

(cl:defvar *require-feature->checkpoint*
  (let ((h (cl:make-hash-table :test 'eq)))
    ;; Minimal feature->checkpoint map to turn `require' into "load when needed"
    ;; without pulling in arbitrary files during bring-up.  We intentionally
    ;; load only a known-safe prefix, then `provide' the feature (these files
    ;; may not reach their upstream (provide ...) within the checkpoint).
    ;; NOTE: `macroexp' and `gv' are provided by clemacs compat stubs; loading a
    ;; partial checkpoint of the upstream files can leave helper functions
    ;; undefined (e.g. gv-get calling gv--defsetter), so avoid checkpoint loads
    ;; for those features until we can load them end-to-end.
    (setf (gethash 'macroexp h) (list :library "macroexp" :max-forms nil))
    (setf (gethash 'gv h)       (list :library "gv"       :max-forms nil
                                      :requires '(macroexp)))
    (setf (gethash 'cl-lib h)   (list :library "cl-lib"   :max-forms 10
                                      :requires '(macroexp gv)))
    (setf (gethash 'cl-macs h)  (list :library "cl-macs"  :max-forms 10
                                      :requires '(cl-lib)))
    h))

(cl:defun require (feature &optional filename noerror)
  "Bring-up subset of ELisp `require'.

If FEATURE is not provided yet, try to load it using a minimal
FEATURE->checkpoint mapping (or FILENAME when provided).  For unknown features
without an explicit FILENAME, keep the old bring-up behavior and only record
FEATURE as provided."
  (when (featurep feature)
    (return-from require feature))
  (cond
   ;; If the caller provided FILENAME, do a normal (full) load.
   (filename
    (let ((lib (cond
                ((stringp filename) filename)
                ((symbolp filename) (symbol-name filename))
                (t (error "ELISP:REQUIRE bad filename: ~S" filename)))))
      (let ((ok (load lib noerror)))
        (when (and (not ok) noerror)
          (return-from require nil))
        (provide feature))))
   (t
    (let ((spec (gethash feature *require-feature->checkpoint*)))
      (when spec
        (let* ((lib (getf spec :library))
               (max-forms (getf spec :max-forms))
               (reqs (getf spec :requires))
               (load-path* (and (boundp 'load-path) (symbol-value 'load-path)))
               (path (and load-path* (locate-file lib load-path* (list (string-to-unibyte ".el"))))))
          (dolist (req reqs)
            (require req nil noerror))
          (when path
            (handler-case
                (if max-forms
                    (load-elisp-file (probe-file (%file-name->cl-string path))
                                     :max-forms max-forms)
                    (load lib noerror))
              (cl:error (e)
                (if noerror
                    (return-from require nil)
                  (error (cl:format nil "ELISP:REQUIRE failed loading ~S: ~A"
                                    lib e))))))))
      ;; Preserve earlier bring-up behavior: if we didn't (or couldn't) load,
      ;; just record the feature.
      (provide feature))))
  feature)

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

(cl:defun file-newer-than-file-p (file1 file2)
  "Bring-up subset of the C primitive `file-newer-than-file-p'."
  (unless (and (stringp file1) (stringp file2))
    (error "ELISP:FILE-NEWER-THAN-FILE-P expects strings, got: %S %S" file1 file2))
  (let* ((p1 (ignore-errors (probe-file (%file-name->cl-string file1))))
         (p2 (ignore-errors (probe-file (%file-name->cl-string file2)))))
    (cond
     ((or (null p1) (null p2)) nil)
     (t
      (let ((t1 (ignore-errors (file-write-date p1)))
            (t2 (ignore-errors (file-write-date p2))))
        (and (integerp t1) (integerp t2) (> t1 t2) t))))))

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

(cl:defun file-name-absolute-p (file)
  "Bring-up subset of the C primitive `file-name-absolute-p'."
  (let ((s (%file-name->cl-string file)))
    (and (> (length s) 0)
         (or (char= (char s 0) #\/)
             (char= (char s 0) #\~))
         t)))

(cl:defun file-name-extension (filename &optional period)
  "Bring-up subset of ELisp `file-name-extension'."
  (let* ((s0 (%file-name->cl-string filename))
         ;; Emacs ignores a trailing backup suffix.
         (s (if (and (> (length s0) 0) (char= (char s0 (1- (length s0))) #\~))
                (subseq s0 0 (1- (length s0)))
                s0))
         (slash (or (position #\/ s :from-end t) -1))
         (dot (position #\. s :from-end t)))
    (cond
     ((or (null dot) (<= dot slash))
      nil)
     (t
      (let ((ext (subseq s (1+ dot))))
        (if period
            (concatenate 'cl:string "." ext)
            ext))))))

(cl:defun file-name-directory (filename)
  "Bring-up subset of ELisp `file-name-directory'."
  (let* ((is-unibyte (unibyte-string-p filename))
         (s (%file-name->cl-string filename))
         (pos1 (position #\/ s :from-end t))
         (pos2 (position #\\ s :from-end t))
         (pos (cond
               ((and pos1 pos2) (max pos1 pos2))
               (pos1 pos1)
               (pos2 pos2)
               (t nil))))
    (when (null pos)
      (return-from file-name-directory nil))
    (let ((dir (subseq s 0 (1+ pos))))
      (if is-unibyte (string-to-unibyte dir) dir))))

(cl:defun file-name-nondirectory (filename)
  "Bring-up subset of ELisp `file-name-nondirectory'."
  (let* ((is-unibyte (unibyte-string-p filename))
         (s (%file-name->cl-string filename))
         (pos1 (position #\/ s :from-end t))
         (pos2 (position #\\ s :from-end t))
         (pos (cond
               ((and pos1 pos2) (max pos1 pos2))
               (pos1 pos1)
               (pos2 pos2)
               (t nil))))
    (let ((base
            (cond
             ((null pos) s)
             ((= pos (1- (length s))) "")
             (t (subseq s (1+ pos))))))
      (if is-unibyte (string-to-unibyte base) base))))

(cl:defun directory-file-name (directory)
  "Bring-up subset of ELisp `directory-file-name'."
  (let* ((is-unibyte (unibyte-string-p directory))
         (s (%file-name->cl-string directory))
         (out s))
    ;; Trim trailing directory separators, but keep "/" as-is.
    (loop while (and (> (length out) 1)
                     (let ((ch (char out (1- (length out)))))
                       (or (char= ch #\/) (char= ch #\\))))
          do (setf out (subseq out 0 (1- (length out)))))
    (if is-unibyte (string-to-unibyte out) out)))

(cl:defun file-truename (filename)
  "Bring-up subset of the C primitive `file-truename'."
  (let* ((s (%file-name->cl-string filename))
         (expanded (expand-file-name s))
         (p (or (probe-file expanded)
                (error "ELISP:FILE-TRUENAME no such file or directory: %S" filename)))
         (tn (truename p))
         (out (namestring tn)))
    ;; Normalize: avoid a trailing slash for directories (matches Emacs).
    (when (and (> (length out) 1)
               (char= (char out (1- (length out))) #\/))
      (setf out (subseq out 0 (1- (length out)))))
    out))

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

(cl:defun file-attribute-type (attributes)
  "Bring-up subset of ELisp `file-attribute-type'."
  (nth 0 attributes))

(cl:defun file-attribute-link-number (attributes)
  "Bring-up subset of ELisp `file-attribute-link-number'."
  (nth 1 attributes))

(cl:defun file-attribute-user-id (attributes)
  "Bring-up subset of ELisp `file-attribute-user-id'."
  (nth 2 attributes))

(cl:defun file-attribute-group-id (attributes)
  "Bring-up subset of ELisp `file-attribute-group-id'."
  (nth 3 attributes))

(cl:defun file-attribute-access-time (attributes)
  "Bring-up subset of ELisp `file-attribute-access-time'."
  (nth 4 attributes))

(cl:defun file-attribute-modification-time (attributes)
  "Bring-up subset of ELisp `file-attribute-modification-time'."
  (nth 5 attributes))

(cl:defun file-attribute-status-change-time (attributes)
  "Bring-up subset of ELisp `file-attribute-status-change-time'."
  (nth 6 attributes))

(cl:defun file-attribute-size (attributes)
  "Bring-up subset of ELisp `file-attribute-size'."
  (nth 7 attributes))

(cl:defun file-attribute-modes (attributes)
  "Bring-up subset of ELisp `file-attribute-modes'."
  (nth 8 attributes))

(cl:defun file-attribute-inode-number (attributes)
  "Bring-up subset of ELisp `file-attribute-inode-number'."
  (nth 10 attributes))

(cl:defun file-attribute-device-number (attributes)
  "Bring-up subset of ELisp `file-attribute-device-number'."
  (nth 11 attributes))

(cl:defun file-attribute-file-identifier (attributes)
  "Bring-up subset of ELisp `file-attribute-file-identifier'."
  (cons (file-attribute-inode-number attributes)
        (file-attribute-device-number attributes)))

(cl:defun copy-file (file newname &optional ok-if-already-exists _time _preserve-uid-gid _preserve-permissions)
  "Bring-up subset of the C primitive `copy-file'."
  (declare (cl:ignore _time _preserve-uid-gid _preserve-permissions))
  (unless (stringp file)
    (error "ELISP:COPY-FILE expected string FILE, got: ~S" file))
  (unless (stringp newname)
    (error "ELISP:COPY-FILE expected string NEWNAME, got: ~S" newname))
  (let* ((src (%expand-tilde-file-name (%file-name->cl-string file)))
         (dst (%expand-tilde-file-name (%file-name->cl-string newname))))
    (unless (probe-file src)
      (error "ELISP:COPY-FILE missing source: %S" (string-to-unibyte src)))
    (when (and (probe-file dst) (not ok-if-already-exists))
      (error "ELISP:COPY-FILE destination exists: %S" (string-to-unibyte dst)))
    (with-open-file (in src :direction :input :element-type '(unsigned-byte 8))
      (with-open-file (out dst
                           :direction :output
                           :if-does-not-exist :create
                           :if-exists (if ok-if-already-exists :supersede :error)
                           :element-type '(unsigned-byte 8))
        (let ((buf (make-array 8192 :element-type '(unsigned-byte 8))))
          (loop for n = (read-sequence buf in)
                while (plusp n) do
                  (write-sequence buf out :end n)))))
    t))

(cl:defun make-symbolic-link (target linkname &optional ok-if-already-exists)
  "Bring-up subset of the C primitive `make-symbolic-link'."
  (unless (stringp target)
    (error "ELISP:MAKE-SYMBOLIC-LINK expected string TARGET, got: ~S" target))
  (unless (stringp linkname)
    (error "ELISP:MAKE-SYMBOLIC-LINK expected string LINKNAME, got: ~S" linkname))
  #+sbcl
  (let* ((src (%expand-tilde-file-name (%file-name->cl-string target)))
         (dst (%expand-tilde-file-name (%file-name->cl-string linkname))))
    (when (and (probe-file dst) (not ok-if-already-exists))
      (error "ELISP:MAKE-SYMBOLIC-LINK destination exists: %S" (string-to-unibyte dst)))
    (handler-case
        (progn
          (when (and ok-if-already-exists (probe-file dst))
            (ignore-errors (uiop:delete-file-if-exists dst)))
          (sb-posix:symlink src dst)
          t)
      (sb-posix:syscall-error (e)
        (error "ELISP:MAKE-SYMBOLIC-LINK failed: %S" e))
      (cl:error (e)
        (error "ELISP:MAKE-SYMBOLIC-LINK failed: %S" e))))
  #-sbcl
  (declare (cl:ignore target linkname ok-if-already-exists))
  #-sbcl
  (error "ELISP:MAKE-SYMBOLIC-LINK unsupported on this host"))

(cl:defun set-file-times (_filename &optional _times _follow-flag)
  "Bring-up stub for the C primitive `set-file-times'."
  (declare (cl:ignore _filename _times _follow-flag))
  t)

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

(cl:defun file-name-all-completions (file directory)
  "Bring-up subset of the C primitive `file-name-all-completions'."
  (unless (stringp file)
    (error "ELISP:FILE-NAME-ALL-COMPLETIONS expected string FILE, got: ~S" file))
  (unless (stringp directory)
    (error "ELISP:FILE-NAME-ALL-COMPLETIONS expected string DIRECTORY, got: ~S" directory))
  (let* ((prefix (%file-name->cl-string file))
         (prefix-len (cl:length prefix))
         (names (directory-files directory nil nil t)))
    (loop for n in names
          for s = (%file-name->cl-string n)
          unless (or (cl:string= s ".") (cl:string= s ".."))
            when (and (cl:>= (cl:length s) prefix-len)
                      (cl:string= prefix (cl:subseq s 0 prefix-len)))
              collect n)))

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

(cl:defun make-directory-internal (dir)
  "Bring-up subset of the C primitive `make-directory-internal'."
  (unless (stringp dir)
    (error "ELISP:MAKE-DIRECTORY-INTERNAL expected string, got: ~S" dir))
  #+sbcl
  (let* ((path (%expand-tilde-file-name (%file-name->cl-string dir)))
         (mode #o777))
    (handler-case
        (progn
          (sb-posix:mkdir path mode)
          nil)
      (sb-posix:syscall-error (e)
        (error "ELISP:MAKE-DIRECTORY-INTERNAL failed for %S: %S"
               (string-to-unibyte path) e))
      (cl:error (e)
        (error "ELISP:MAKE-DIRECTORY-INTERNAL failed for %S: %S"
               (string-to-unibyte path) e))))
  #-sbcl
  (declare (cl:ignore dir))
  #-sbcl
  (error "ELISP:MAKE-DIRECTORY-INTERNAL unsupported on this host"))

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
