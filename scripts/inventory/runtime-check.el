;;; runtime-check.el --- validate static variable/symbol inventory -*- lexical-binding: t; -*-

(require 'json)
(require 'subr-x)

(defun clmacs--read-jsonl (path)
  (let (items)
    (with-temp-buffer
      (insert-file-contents path)
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (string-trim (buffer-substring-no-properties
                                  (line-beginning-position)
                                  (line-end-position)))))
          (unless (or (string-empty-p line) (string-prefix-p "#" line))
            (push (json-parse-string line :object-type 'alist :array-type 'list)
                  items)))
        (forward-line 1)))
    (nreverse items)))

(let* ((jsonl (or (getenv "CLMACS_INVENTORY_JSONL")
                  (error "CLMACS_INVENTORY_JSONL is required")))
       (items (clmacs--read-jsonl jsonl))
       (unbound-vars '())
       (missing-syms '()))
  (dolist (it items)
    (let* ((kind (alist-get "kind" it))
           (name (alist-get "lisp_name" it)))
      (cond
       ((equal kind "variable")
        (let ((sym (intern-soft name)))
          (cond
           ((null sym) (push name missing-syms))
           ((not (boundp sym)) (push name unbound-vars)))))
       ((equal kind "symbol")
        (unless (intern-soft name)
          (push name missing-syms))))))
  (setq unbound-vars (sort unbound-vars #'string<))
  (setq missing-syms (sort missing-syms #'string<))
  (princ
   (json-serialize
    (list
     :unbound_variables (vconcat unbound-vars)
     :missing_symbols (vconcat missing-syms))
    :null-object :null :false-object nil)))
