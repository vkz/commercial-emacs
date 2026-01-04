(in-package #:clemacs.test)

(fiveam:def-suite clemacs-smoke)
(fiveam:in-suite clemacs-smoke)

(defun %maybe-emacs-prin1 (expr)
  (handler-case
      (multiple-value-bind (out err code)
          (uiop:run-program
           (list "emacs" "-Q" "--batch" "--eval"
                 (format nil "(let ((print-escape-newlines t) (print-escape-control-characters t)) (prin1 ~A) (terpri))"
                         expr))
           :output :string
           :error-output :string
           :ignore-error-status t)
        (when (not (eql code 0))
          (error "emacs -Q --batch failed (~S): ~A" code err))
        (string-trim '(#\Space #\Tab #\Newline #\Return) out))
    (error () nil)))

(defun %clemacs-prin1 (value)
  (labels ((p1 (v)
             (cond
              ((vectorp v)
               (with-output-to-string (s)
                 (write-char #\[ s)
                 (dotimes (i (length v))
                   (when (> i 0) (write-char #\Space s))
                   (write-string (p1 (aref v i)) s))
                 (write-char #\] s)))
              (t
               (let ((*package* (find-package "ELISP"))
                     (*print-case* :downcase)
                     (*print-pretty* nil)
                     (*print-escape* t))
                 (prin1-to-string v))))))
    (p1 value)))

(defun %elisp-eval-1 (string)
  (let ((*package* (find-package "ELISP"))
        (*readtable* (elisp::%ensure-elisp-readtable)))
    (cl:eval (read-from-string string))))

(defun %elisp-read-1 (string)
  (let ((*package* (find-package "ELISP"))
        (*readtable* (elisp::%ensure-elisp-readtable)))
    (read-from-string string)))

(fiveam:test substrate-basics
  (let ((version (clemacs:substrate-version))
        (platform (clemacs:substrate-platform)))
    (fiveam:is (and (stringp version) (> (length version) 0)))
    (fiveam:is (and (stringp platform) (> (length platform) 0))))

  (fiveam:is (= (clemacs:substrate-parse-int "42") 42))
  (fiveam:signals clemacs:clemacs-substrate-error
    (clemacs:substrate-parse-int "nope")))

(fiveam:test handle-table
  (let* ((table (clemacs:make-handle-table))
         (h1 (clemacs:handle-alloc table 'a))
         (h2 (clemacs:handle-alloc table 'b)))
    (fiveam:is (eql (clemacs:handle-get table h1) 'a))
    (fiveam:is (eql (clemacs:handle-get table h2) 'b))
    (fiveam:is (clemacs:handle-free table h1))
    (fiveam:signals error
      (clemacs:handle-get table h1))
    (let ((h3 (clemacs:handle-alloc table 'c)))
      (fiveam:is (eql h3 h1))
      (fiveam:is (eql (clemacs:handle-get table h3) 'c)))))

(fiveam:test buffer-edit-basics
  (let ((b (clemacs:make-buffer :content "")))
    (fiveam:is (= (clemacs:buffer-length b) 0))
    (clemacs:buffer-insert-string b "abc")
    (fiveam:is (string= (clemacs:buffer-text b) "abc"))
    (fiveam:is (= (clemacs:buffer-point b) 3))
    (clemacs:buffer-backward-char b)
    (clemacs:buffer-insert-char b #\X)
    (fiveam:is (string= (clemacs:buffer-text b) "abXc"))
    (fiveam:is (= (clemacs:buffer-point b) 3))
    (clemacs:buffer-delete-backward b)
    (fiveam:is (string= (clemacs:buffer-text b) "abc"))
    (fiveam:is (= (clemacs:buffer-point b) 2))
    (values)))

(fiveam:test buffer-vertical-motion
  (let* ((b (clemacs:make-buffer :content (format nil "abc~%line2")))
         (initial-point (clemacs:buffer-point b)))
    (fiveam:is (= initial-point 9))
    (multiple-value-bind (b2 goal)
        (clemacs:buffer-move-vertical b -1 :goal-column nil)
      (declare (ignore b2))
      (fiveam:is (= goal 5)))
    (multiple-value-bind (line col) (clemacs::buffer-line-column b)
      (fiveam:is (= line 0))
      (fiveam:is (= col 3)))))

(fiveam:test elisp-compat
  (let ((exprs '(("(progn (setq x 1) x)" . "1")
                 ("(let ((p nil)) (setq p (plist-put p 'a 1)) (plist-get p 'a))" . "1")
                 ("[1 2 3]" . "[1 2 3]")
                 ("?a" . "97"))))
    (dolist (item exprs)
      (destructuring-bind (expr . expected) item
        (let ((value (%elisp-eval-1 expr)))
          (fiveam:is (string= (%clemacs-prin1 value) expected))
          (let ((emacs-out (%maybe-emacs-prin1 expr)))
            (if emacs-out
                (fiveam:is (string= emacs-out expected))
                (fiveam:skip "emacs not on PATH"))))))))

(fiveam:test elisp-reader-backquote
  (let* ((form (%elisp-read-1 "`(a ,b ,@c)")))
    (fiveam:is (and (consp form) (string= (cl:symbol-name (car form)) "`")))
    (let* ((elisp (find-package "ELISP"))
           (comma (cl:intern "," elisp))
           (comma-at (cl:intern ",@" elisp)))
      (fiveam:is
       (equal
        (second form)
        (list (cl:intern "A" elisp)
              (list comma (cl:intern "B" elisp))
              (list comma-at (cl:intern "C" elisp))))))))

(fiveam:test elisp-backquote-vectors
  (let* ((project-root
           (uiop:ensure-directory-pathname
            (or (uiop:getenv "MISE_PROJECT_ROOT")
                (uiop:pathname-parent-directory-pathname
                 (asdf:system-source-directory :clemacs)))))
         (backquote-el (merge-pathnames #p"lisp/emacs-lisp/backquote.el" project-root)))
    (unless (fboundp 'elisp::backquote)
      (elisp::load-elisp-file backquote-el))
    (let ((value (%elisp-eval-1 "`(x [0 255])")))
    (fiveam:is (and (consp value) (eql (car value) 'elisp::x)))
    (fiveam:is (vectorp (cadr value)))
    (fiveam:is (= (length (cadr value)) 2))
    (fiveam:is (= (aref (cadr value) 0) 0))
    (fiveam:is (= (aref (cadr value) 1) 255)))))

(fiveam:test elisp-pcase-dolist-simple
  (let ((value
          (%elisp-eval-1
           "(let ((states '((a t 1) (b nil 2))) (out nil)) (pcase-dolist (`(,v ,l ,val) states) (setq out (cons v out))) out)")))
    (fiveam:is (string= (%clemacs-prin1 value) "(b a)"))))

(defun run-smoke (&key (stream *standard-output*))
  (let ((fiveam:*test-dribble* stream))
    (multiple-value-bind (ok failed skipped)
        (fiveam:run! 'clemacs-smoke)
      (declare (ignore failed skipped))
      (format stream "clemacs smoke: ~:[FAIL~;ok~]~%" ok)
      (finish-output stream)
      (if ok 0 1))))
