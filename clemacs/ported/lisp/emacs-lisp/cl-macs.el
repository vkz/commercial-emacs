;;; cl-macs.el --- clemacs minimal cl-macs subset  -*- lexical-binding: t; -*-

;; This file is NOT part of GNU Emacs.
;;
;; clemacs port/stub:
;; - The upstream `cl-macs.el` is compile-time heavy.
;; - clemacs bring-up historically loads it with a low max-forms cap, and
;;   upstream `cl-generic.el` expects core macros like `cl-letf`.
;; - Provide a small, self-contained subset of `cl-macs` sufficient for
;;   clemacs startup + upstream ERT bring-up, without loading the full upstream
;;   file.

;;; Code:

(defmacro cl-letf (bindings &rest body)
  "Temporarily bind to PLACEs.

Bring-up subset: supports (symbol-function 'SYM) and (symbol-value 'SYM) places.

(fn ((PLACE VALUE) ...) BODY...)"
  (declare (indent 1))
  (let ((saves nil)
        (sets nil)
        (restores nil))
    (dolist (binding bindings)
      (unless (consp binding)
        (error "cl-letf: bad binding: %S" binding))
      (let ((place (car binding))
            (value (cadr binding)))
        (pcase place
          (`(symbol-function ',sym)
           (let ((old (make-symbol "cl-letf-old-fn")))
             (push `(,old (symbol-function ',sym)) saves)
             (push `(fset ',sym ,value) sets)
             (push `(fset ',sym ,old) restores)))
          (`(symbol-value ',sym)
           (let ((old (make-symbol "cl-letf-old-val")))
             (push `(,old (symbol-value ',sym)) saves)
             (push `(set ',sym ,value) sets)
             (push `(set ',sym ,old) restores)))
          (_
           (error "cl-letf: unsupported place (bring-up subset): %S" place)))))
    `(let ,(nreverse saves)
       (unwind-protect
           (progn ,@(nreverse sets) ,@body)
         ,@(nreverse restores)))))

(defmacro cl-letf* (bindings &rest body)
  "Temporarily bind to PLACEs sequentially.
Bring-up subset: implemented by nesting `cl-letf'."
  (declare (indent 1))
  (dolist (binding (reverse bindings))
    (setq body (list `(cl-letf (,binding) ,@body))))
  `(progn ,@body))

(defmacro cl-flet (bindings &rest body)
  "Make local function definitions.

Bring-up subset: binds function cells (no macroexp environment tricks).

(fn ((NAME ARGLIST BODY...) ...) FORM...)"
  (declare (indent 1))
  `(cl-letf
       ,(mapcar
         (lambda (binding)
           (let ((name (car binding))
                 (args-and-body (cdr binding)))
             (list
              (list 'symbol-function (list 'quote name))
              (if (= (length args-and-body) 1)
                  (car args-and-body)
                (list 'function
                      (cons 'lambda args-and-body))))))
         bindings)
     ,@body))

(defmacro cl-flet* (bindings &rest body)
  "Make local function definitions.
Like `cl-flet' but the definitions can refer to previous ones.

Bring-up subset: implemented via nested `cl-flet'."
  (declare (indent 1))
  (cond
   ((null bindings) `(progn ,@body))
   ((null (cdr bindings)) `(cl-flet ,bindings ,@body))
   (t `(cl-flet (,(car bindings)) (cl-flet* ,(cdr bindings) ,@body)))))

(provide 'cl-macs)

;;; cl-macs.el ends here
