(in-package #:elisp)

(define-condition ert-failure (error)
  ((form :initarg :form :reader ert-failure-form))
  (:report (lambda (c s)
             (format s "ERT failure: ~S" (ert-failure-form c)))))

(defvar *ert-tests* (make-hash-table :test 'eq))

(defun ert-reset ()
  (clrhash *ert-tests*)
  t)

(defmacro ert-deftest (name args &body body)
  `(progn
     (setf (gethash ',name *ert-tests*)
           (lambda ,args ,@body))
     ',name))

(defmacro should (form)
  `(unless ,form
     (error 'ert-failure :form ',form)))

(defun ert-run-tests-batch (&key (stream *standard-output*))
  (let ((total 0)
        (failed 0))
    (maphash
     (lambda (name fn)
       (incf total)
       (handler-case
           (progn
             (funcall fn)
             (format stream "ok  ~S~%" name))
         (error (e)
           (incf failed)
           (format stream "FAIL ~S: ~A~%" name e))))
     *ert-tests*)
    (format stream "ert: ~D total, ~D failed~%" total failed)
    (finish-output stream)
    (if (zerop failed) 0 1)))
