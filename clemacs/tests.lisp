(in-package #:clemacs.test)

(defun %assert (pred fmt &rest args)
  (unless pred
    (error "~?." fmt args)))

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

  (format stream "clemacs smoke: ok~%")
  (finish-output stream)
  0)
