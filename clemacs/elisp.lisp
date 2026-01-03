(in-package #:elisp)

(defvar *elisp-readtable* nil)

(cl:defun %ensure-elisp-readtable ()
  (or *elisp-readtable*
      (let ((rt (copy-readtable nil)))
        (set-dispatch-macro-character
         #\#
         #\'
         (lambda (stream sub-char arg)
           (declare (ignore sub-char arg))
           (list (cl:intern "FUNCTION" (find-package "ELISP"))
                 (read stream t nil t)))
         rt)
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

(cl:defun load-elisp-file (path &key (package (find-package "ELISP")))
  (with-open-file (in path :external-format :utf-8)
    (let ((*package* package)
          (*readtable* (%ensure-elisp-readtable)))
      (loop with form-index = 0
            for form = (read in nil :eof)
            until (eq form :eof)
            do
              (incf form-index)
              (handler-case
                  (eval form)
                (error (e)
                  (let ((inv (inventory-entry-for-condition
                              e
                              :start-dir (uiop:pathname-directory-pathname path))))
                    (error 'elisp-load-error
                           :path path
                           :form-index form-index
                           :form form
                           :cause e
                           :inventory-entry inv))))))))
