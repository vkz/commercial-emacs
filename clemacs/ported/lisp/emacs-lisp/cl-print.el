;;; cl-print.el --- clemacs ported stub for cl-print  -*- lexical-binding: t; -*-

;; This fork intentionally does not support bytecode objects during clemacs
;; bring-up, but upstream `nadvice-tests.el` uses `cl-prin1-to-string` to
;; validate advice printing.  Provide a small, compatible subset without
;; pulling in upstream `cl-print.el`'s byte-code specializers.

;;; Code:

(cl-defgeneric oclosure-interactive-form (object &optional command)
  "Bring-up subset hook for OClosure-specific interactive specs.

`nadvice.el` extends this generic so advice wrappers can synthesize a combined
interactive spec from their component functions."
  (declare (ignore object command))
  nil)

(defun cl--print-object (object stream)
  "Bring-up subset printer used by `cl-prin1-to-string`."
  (cond
   ((and (fboundp 'advice--p)
         (ignore-errors (advice--p object))
         (fboundp 'advice--car)
         (fboundp 'advice--how)
         (fboundp 'advice--cdr))
    (princ "#f(advice " stream)
    (cl--print-object (advice--car object) stream)
    (princ " " stream)
    (prin1 (advice--how object) stream)
    (princ " " stream)
    (cl--print-object (advice--cdr object) stream)
    (when (fboundp 'advice--props)
      (let ((props (ignore-errors (advice--props object))))
        (when props
          (princ " " stream)
          (cl--print-object props stream))))
    (princ ")" stream))
   (t
    (prin1 object stream))))

(cl-defgeneric cl-print-object (object stream)
  "Print OBJECT to STREAM (bring-up subset)."
  (cl--print-object object stream))

(defun cl-prin1-to-string (object)
  "Return a printed representation of OBJECT.

Bring-up subset: use `cl-print-object` if present (notably for `nadvice`),
otherwise fall back to `prin1-to-string`."
  (cl:with-output-to-string (s)
    (cl-print-object object s)))

(provide 'cl-print)

;;; cl-print.el ends here
