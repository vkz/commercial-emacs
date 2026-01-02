;;; runtime-subrs.el --- dump subr inventory -*- lexical-binding: t; -*-

(require 'json)

(defun clmacs--subr-arity-record (fn)
  (let ((a (ignore-errors (subr-arity fn))))
    (cond
     ((consp a)
      (let ((min (car a))
            (max (cdr a)))
        (list :min (if (integerp min) min :null)
              :max (if (integerp max) max :null)
              :raw (prin1-to-string a))))
     ((null a)
      (list :min :null :max :null :raw :null))
     (t
      (list :min :null :max :null :raw (prin1-to-string a))))))

(let (items)
  (let ((seen (make-hash-table :test 'equal)))
    ;; Collect by canonical subr name, not by symbol.  Many symbols are
    ;; function-aliases pointing at the same subr.
    (mapatoms
     (lambda (sym)
       (when (fboundp sym)
         (let ((fn (symbol-function sym)))
           (when (subrp fn)
             (let* ((name (subr-name fn))
                    (canon-sym (or (intern-soft name) sym))
                    (kind (if (special-form-p canon-sym) "special_form" "subr"))
                    (doc (ignore-errors (documentation canon-sym t)))
                    (arity (clmacs--subr-arity-record fn)))
               (puthash name
                        (list
                         :kind kind
                         :lisp_name name
                         :doc_present (and (stringp doc) (> (length doc) 0))
                         :arity (list
                                 :min (plist-get arity :min)
                                 :max (plist-get arity :max)
                                 :raw (plist-get arity :raw)))
                        seen)))))))
    (maphash (lambda (_ v) (push v items)) seen))
  (setq items (sort items (lambda (a b) (string< (plist-get a :lisp_name)
                                                (plist-get b :lisp_name)))))
  (setq items (vconcat items))
  (princ (json-serialize items :null-object :null :false-object nil)))
