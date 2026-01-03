(in-package #:elisp)

(defvar *elisp-readtable* nil)

(cl:defun %elisp-rewrite (form)
  (labels ((rw (x)
             (cond
              ((atom x) x)
              ;; Do not rewrite under QUOTE.
              ((and (consp x) (eq (car x) 'quote) (= (length x) 2))
               x)
              ;; Rewrite FUNCTION only when it wraps a lambda form.
              ((and (consp x) (eq (car x) 'function) (= (length x) 2))
               (let ((arg (cadr x)))
                 (if (and (consp arg) (eq (car arg) 'lambda))
                     (list 'function (rw arg))
                     x)))
              ;; ELisp IF allows multiple else forms; CL:IF does not.
              ((and (consp x) (eq (car x) 'cl:if))
               (destructuring-bind (op test then &rest else) x
                 (declare (ignore op))
                 (cond
                  ((null else) (list 'cl:if (rw test) (rw then) nil))
                  ((null (cdr else)) (list 'cl:if (rw test) (rw then) (rw (car else))))
                  (t (list 'cl:if (rw test) (rw then) (cons 'progn (mapcar #'rw else)))))))
              ;; Prefer an ELisp-aware HANDLER-BIND shim so handlers receive
              ;; ELisp-style error data (SYMBOL . DATA), rather than CL
              ;; condition objects.
              ((and (consp x) (eq (car x) 'cl:handler-bind))
               (destructuring-bind (op bindings &rest body) x
                 (declare (ignore op))
                 (cons 'elisp::handler-bind
                       (cons (mapcar #'rw bindings)
                             (mapcar #'rw body)))))
              ;; General cons rewrite: preserve dotted lists.
              (t (cons (rw (car x)) (rw (cdr x)))))))
    (rw form)))

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

(cl:defun load-elisp-file (path &key (package (find-package "ELISP")) (max-forms nil))
  (with-open-file (in path :external-format :utf-8)
    (let ((*package* package)
          (*readtable* (%ensure-elisp-readtable)))
      (loop with form-index = 0
            for form = (read in nil :eof)
            until (eq form :eof)
            do
              (incf form-index)
              (handler-case
                  (eval (%elisp-rewrite form))
                (error (e)
                  (let ((inv (inventory-entry-for-condition
                              e
                              :start-dir (uiop:pathname-directory-pathname path))))
                    (error 'elisp-load-error
                           :path path
                           :form-index form-index
                           :form form
                           :cause e
                           :inventory-entry inv))))
              (when (and max-forms (>= form-index max-forms))
                (return))))))
