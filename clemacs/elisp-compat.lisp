(in-package #:elisp)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "SB-CLTL2"))

(defun equal (a b)
  (cond
   ((and (vectorp a) (vectorp b))
    (and (= (length a) (length b))
         (loop for i from 0 below (length a)
               always (equal (aref a i) (aref b i)))))
   (t (cl:equal a b))))

(defun %lexical-variable-p (symbol env)
  (multiple-value-bind (kind)
      (sb-cltl2:variable-information symbol env)
    (eq kind :lexical)))

(defmacro setq (&environment env &rest pairs)
  (unless (evenp (length pairs))
    (error "ELISP:SETQ expects an even number of arguments"))

  (let ((forms nil))
    (loop for (var val) on pairs by #'cddr do
      (unless (symbolp var)
        (error "ELISP:SETQ only supports symbol variables, got: ~S" var))
      (push (if (%lexical-variable-p var env)
                `(cl:setq ,var ,val)
                `(setf (symbol-value ',var) ,val))
            forms))
    `(progn ,@(nreverse forms))))

(defun plist-get (plist prop)
  (getf plist prop))

(defun plist-put (plist prop value)
  (let ((p plist))
    (setf (getf p prop) value)
    p))
