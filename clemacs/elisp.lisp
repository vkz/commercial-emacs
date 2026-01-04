(in-package #:elisp)

(defvar *elisp-readtable* nil)

(defconstant +char-alt+ #x0400000)
(defconstant +char-super+ #x0800000)
(defconstant +char-hyper+ #x1000000)
(defconstant +char-shift+ #x2000000)
(defconstant +char-ctl+ #x4000000)
(defconstant +char-meta+ #x8000000)

(cl:defun %controlify-ascii (code)
  (cond
   ((or (<= (char-code #\A) code (char-code #\Z))
        (<= (char-code #\a) code (char-code #\z))
        (<= (char-code #\@) code (char-code #\_)))
    (logand code #x1f))
   (t nil)))

(cl:defun %read-elisp-escape-code (stream first)
  (labels ((read-hex ()
             (let ((digits nil))
               (loop for ch = (peek-char nil stream nil nil t)
                     while (and ch (digit-char-p ch 16)) do
                       (push (read-char stream nil nil t) digits))
               (unless digits
                 (cl:error "Missing hex digits in ?\\x escape"))
               (parse-integer (coerce (nreverse digits) 'string) :radix 16)))
           (read-octal (first-digit)
             (let ((digits (list first-digit)))
               (loop repeat 2
                     for ch = (peek-char nil stream nil nil t)
                     while (and ch (digit-char-p ch 8)) do
                       (push (read-char stream nil nil t) digits))
               (parse-integer (coerce (nreverse digits) 'string) :radix 8))))
    (case first
      (#\n (char-code #\Newline))
      (#\t (char-code #\Tab))
      (#\r (char-code #\Return))
      (#\s (char-code #\Space))
      (#\b 8)
      (#\f 12)
      (#\a 7)
      (#\e 27)
      (#\\ (char-code #\\))
      (#\" (char-code #\"))
      (#\x (read-hex))
      (otherwise
       (cond
        ((digit-char-p first 8)
         (read-octal first))
        (t
         (char-code first)))))))

(cl:defun %read-elisp-char-literal (stream)
  (let ((c (read-char stream nil nil t)))
    (when (null c)
      (cl:error "EOF after ?"))
    (if (not (char= c #\\))
        (char-code c)
        (let ((bits 0)
              (ctlp nil))
          (labels ((add-mod (m)
                     (case m
                       (#\A (incf bits +char-alt+))
                       (#\H (incf bits +char-hyper+))
                       (#\M (incf bits +char-meta+))
                       (#\s (incf bits +char-super+))
                       (#\S (incf bits +char-shift+))
                       (#\C (setf ctlp t))
                       (otherwise (cl:error "Unknown char modifier: ~S" m))))
                   (finish (code)
                     (let ((ctl-code (and ctlp (%controlify-ascii code))))
                       (cond
                        ((and ctlp (= code 0))
                         (+ bits +char-ctl+))
                        (ctl-code
                         (+ bits ctl-code))
                        (ctlp
                         (+ bits +char-ctl+ code))
                        (t
                         (+ bits code)))))
                   (read-base-code ()
                     (let ((ch (read-char stream nil nil t)))
                       (when (null ch)
                         (cl:error "EOF in ?\\ escape"))
                       (if (char= ch #\\)
                           (let ((e (read-char stream nil nil t)))
                             (when (null e)
                               (cl:error "EOF in ?\\ escape"))
                             (%read-elisp-escape-code stream e))
                           (char-code ch)))))
            ;; Parse a possibly-modified char like: ?\C-\M-a or ?\A-\0.
            (loop
              for ch = (read-char stream nil nil t) do
                (when (null ch)
                  (cl:error "EOF in ?\\ escape"))
                (let ((dash (peek-char nil stream nil nil t)))
                  (cond
                   ((and dash (char= dash #\-) (find ch "ACHMsSC" :test #'char=))
                    (read-char stream nil nil t) ; consume '-'
                    (add-mod ch)
                    (let ((next (peek-char nil stream nil nil t)))
                      (when (null next)
                        (cl:error "EOF in ?\\ escape"))
                      (if (char= next #\\)
                          (read-char stream nil nil t) ; consume '\' and loop
                          (return (finish (read-base-code))))))
                   (t
                    (return (finish (%read-elisp-escape-code stream ch))))))))))))

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
           (%read-elisp-char-literal stream))
         nil
         rt)
        (setf *elisp-readtable* rt))))

(cl:defun load-elisp-file (path &key (package (find-package "ELISP")) (max-forms nil))
  (with-open-file (in path :external-format :utf-8)
    (let* ((*package* package)
           (*readtable* (%ensure-elisp-readtable))
           (debug-file (uiop:getenv "CLEMACS_LOAD_DEBUG_FILE"))
           (debugp (or debug-file (and (uiop:getenv "CLEMACS_LOAD_DEBUG") t))))
      (flet ((%maybe-log-load-error (e form-index)
               (when debugp
                 (let ((out (if debug-file
                                (open debug-file
                                      :direction :output
                                      :if-exists :append
                                      :if-does-not-exist :create)
                                *standard-output*)))
                   (unwind-protect
                       (progn
                         (cl:format out "[clemacs:load] error in ~A form ~D: ~A~%"
                                    path form-index e)
                         #+sbcl
                         (sb-debug:print-backtrace :stream out :count 80)
                         (finish-output out))
                     (when debug-file
                       (ignore-errors (close out))))))))
        (loop with form-index = 0 do
          (let ((form
                  (handler-case
                      (read in nil :eof)
                    (cl:error (e)
                      (let ((next-index (1+ form-index)))
                        (%maybe-log-load-error e next-index)
                        (let ((inv (inventory-entry-for-condition
                                    e
                                    :start-dir (uiop:pathname-directory-pathname path))))
                          (cl:error 'elisp-load-error
                                    :path path
                                    :form-index next-index
                                    :form :read-error
                                    :cause e
                                    :inventory-entry inv)))))))
            (when (eq form :eof)
              (return))
            (incf form-index)
            (handler-case
                (cl:handler-bind
                    ((cl:error
                       (lambda (e)
                         (%maybe-log-load-error e form-index)
                         nil)))
                  (cl:eval (%elisp-rewrite form)))
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
              (return))))))))
