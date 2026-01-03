(in-package #:elisp)

(defvar *elisp-readtable* nil)

(defun %ensure-elisp-readtable ()
  (or *elisp-readtable*
      (let ((rt (copy-readtable nil)))
        (set-macro-character
         #\[
         (lambda (stream char)
           (declare (ignore char))
           (coerce (read-delimited-list #\] stream t) 'vector))
         nil
         rt)
        (set-macro-character
         #\]
         (lambda (stream char)
           (declare (ignore stream char))
           (error "unexpected ]"))
         nil
         rt)
        (set-macro-character
         #\?
         (lambda (stream char)
           (declare (ignore char))
           (let ((c (read-char stream nil nil t)))
             (when (null c)
               (error "EOF after ?"))
             (if (char= c #\\)
                 (let ((e (read-char stream nil nil t)))
                   (when (null e)
                     (error "EOF in ?\\ escape"))
                   (case e
                     (#\n (char-code #\Newline))
                     (#\t (char-code #\Tab))
                     (#\r (char-code #\Return))
                     (#\s (char-code #\Space))
                     (#\\ (char-code #\\))
                     (otherwise (char-code e))))
                 (char-code c))))
         nil
         rt)
        (setf *elisp-readtable* rt))))

(defun load-elisp-file (path &key (package (find-package "ELISP")))
  (with-open-file (in path :external-format :utf-8)
    (let ((*package* package)
          (*readtable* (%ensure-elisp-readtable)))
      (loop for form = (read in nil :eof)
            until (eq form :eof)
            do (eval form)))))
