(in-package #:elisp)

(defun plist-get (plist prop)
  (getf plist prop))

(defun plist-put (plist prop value)
  (let ((p plist))
    (setf (getf p prop) value)
    p))
