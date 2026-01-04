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
        ;; Emacs Lisp backquote/unquote are not reader macros in the CL sense:
        ;; they read into explicit forms using the symbols `\, and \,@.
        ;; This is important because ELisp code expects to see those symbols
        ;; (e.g. backquote.el and pcase patterns).
        (let ((bq (cl:intern "`" (find-package "ELISP")))
              (uq (cl:intern "," (find-package "ELISP")))
              (sp (cl:intern ",@" (find-package "ELISP"))))
          (set-macro-character
           #\`
           (lambda (stream char)
             (declare (ignore char))
             (list bq (read stream t nil t)))
           nil
           rt)
          (set-macro-character
           #\,
           (lambda (stream char)
             (declare (ignore char))
             (let ((next (peek-char nil stream nil nil t)))
               (cond
                ((and next (char= next #\@))
                 (read-char stream nil nil t)
                 (list sp (read stream t nil t)))
                (t
                 (list uq (read stream t nil t))))))
           nil
           rt))
        (set-macro-character
         #\"
         (lambda (stream char)
           (declare (ignore char))
           (with-output-to-string (out)
             (loop
               for ch = (read-char stream nil nil t) do
                 (when (null ch)
                   (cl:error "EOF while reading string"))
                 (cond
                  ((char= ch #\")
                   (return))
                  ((char= ch #\\)
                   (let ((e (read-char stream nil nil t)))
                     (when (null e)
                       (cl:error "EOF in string escape"))
                     (case e
                       (#\n (write-char #\Newline out))
                       (#\t (write-char #\Tab out))
                       (#\r (write-char #\Return out))
                       (#\b (write-char (code-char 8) out))
                       (#\f (write-char (code-char 12) out))
                       (#\a (write-char (code-char 7) out))
                       (#\e (write-char (code-char 27) out))
                       (#\\ (write-char #\\ out))
                       (#\" (write-char #\" out))
                       (#\Newline nil) ; line continuation
                       (otherwise (write-char e out)))))
                  (t
                   (write-char ch out))))))
         nil
         rt)
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
           (cl:error "unexpected ]"))
         nil
         rt)
        (set-macro-character
         #\?
         (lambda (stream char)
           (declare (ignore char))
           (let ((c (read-char stream nil nil t)))
             (when (null c)
               (cl:error "EOF after ?"))
             (if (char= c #\\)
                 (let ((e (read-char stream nil nil t)))
                   (when (null e)
                     (cl:error "EOF in ?\\ escape"))
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
                  (cl:eval (%elisp-rewrite form))
                (cl:error (e)
                  (let ((inv (inventory-entry-for-condition
                              e
                              :start-dir (uiop:pathname-directory-pathname path))))
                    (cl:error 'elisp-load-error
                           :path path
                           :form-index form-index
                           :form form
                           :cause e
                           :inventory-entry inv))))
              (when (and max-forms (>= form-index max-forms))
                (return))))))
