(in-package #:clemacs.test)

(defun %assert (pred fmt &rest args)
  (unless pred
    (error "~?." fmt args)))

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
    (eval (read-from-string string))))

(defun run-smoke (&key (stream *standard-output*))
  (let ((version (clemacs:substrate-version))
        (platform (clemacs:substrate-platform)))
    (%assert (and (stringp version) (> (length version) 0))
             "substrate version is invalid: ~S" version)
    (%assert (and (stringp platform) (> (length platform) 0))
             "substrate platform is invalid: ~S" platform))

  (let* ((table (clemacs:make-handle-table))
         (h1 (clemacs:handle-alloc table 'a))
         (h2 (clemacs:handle-alloc table 'b)))
    (%assert (eql (clemacs:handle-get table h1) 'a)
             "handle-get mismatch for h1")
    (%assert (eql (clemacs:handle-get table h2) 'b)
             "handle-get mismatch for h2")
    (%assert (clemacs:handle-free table h1)
             "handle-free returned nil for h1")
    (handler-case
        (progn
          (clemacs:handle-get table h1)
          (%assert nil "expected handle-get to fail for freed handle"))
      (error () nil))
    (let ((h3 (clemacs:handle-alloc table 'c)))
      (%assert (eql h3 h1)
               "expected handle reuse; got h3=~S h1=~S" h3 h1)
      (%assert (eql (clemacs:handle-get table h3) 'c)
               "handle-get mismatch for h3")))

  (%assert (= (clemacs:substrate-parse-int "42") 42)
           "substrate-parse-int failed for valid input")
  (handler-case
      (progn
        (clemacs:substrate-parse-int "nope")
        (%assert nil "expected substrate-parse-int to error"))
    (clemacs:clemacs-substrate-error () nil))

  ;; B1-3: restricted Elisp subset loader cross-check (if system emacs exists).
  (let* ((exprs '(("(progn (setq x 1) x)" . "1")
                  ("(let ((p nil)) (setq p (plist-put p 'a 1)) (plist-get p 'a))" . "1")
                  ("[1 2 3]" . "[1 2 3]")
                  ("?a" . "97")))
         (emacs-present nil))
    (dolist (item exprs)
      (destructuring-bind (expr . expected) item
        (let ((value (%elisp-eval-1 expr)))
          (%assert (string= (%clemacs-prin1 value) expected)
                   "clemacs elisp mismatch for ~A: got ~S expected ~S"
                   expr (%clemacs-prin1 value) expected)
          (let ((emacs-out (%maybe-emacs-prin1 expr)))
            (when emacs-out
              (setf emacs-present t)
              (%assert (string= emacs-out expected)
                       "emacs baseline mismatch for ~A: got ~S expected ~S"
                       expr emacs-out expected))))))
    (when (not emacs-present)
      (format stream "clemacs smoke: WARNING: `emacs` not found; skipped baseline cross-check~%")))

  (format stream "clemacs smoke: ok~%")
  (finish-output stream)
  0)
