(in-package #:elisp)

;; ---------------------------------------------------------------------------
;; Minimal ewoc surface (enough for upstream ERT results printing bring-up)
;; ---------------------------------------------------------------------------

(defstruct elisp-ewoc-node
  (data nil)
  (location 1 :type integer))

(defstruct elisp-ewoc
  (buffer nil)
  (pretty-printer nil)
  (header "" :type (or cl:string unibyte-string))
  (footer "" :type (or cl:string unibyte-string))
  (nosep nil)
  (nodes nil))

(cl:defun ewoc-create (pretty-printer &optional header footer nosep)
  "Bring-up subset of ELisp `ewoc-create'.

This is a minimal stub used to get upstream ERT's results buffer printing
working. It stores nodes out-of-band and (re)renders on `ewoc-refresh' and
`ewoc-set-hf'."
  (make-elisp-ewoc :buffer (current-buffer)
                   :pretty-printer pretty-printer
                   :header (or header "")
                   :footer (or footer "")
                   :nosep (and nosep t)
                   :nodes nil))

(cl:defun ewoc-set-hf (ewoc header footer)
  "Bring-up subset of ELisp `ewoc-set-hf'."
  (unless (elisp-ewoc-p ewoc)
    (error "ELISP:EWOC-SET-HF expected ewoc, got: ~S" ewoc))
  (setf (elisp-ewoc-header ewoc) (or header "")
        (elisp-ewoc-footer ewoc) (or footer ""))
  (ewoc-refresh ewoc)
  nil)

(cl:defun ewoc-enter-last (ewoc data)
  "Bring-up subset of ELisp `ewoc-enter-last'."
  (unless (elisp-ewoc-p ewoc)
    (error "ELISP:EWOC-ENTER-LAST expected ewoc, got: ~S" ewoc))
  (let ((node (make-elisp-ewoc-node :data data)))
    (setf (elisp-ewoc-nodes ewoc)
          (nconc (elisp-ewoc-nodes ewoc) (list node)))
    node))

(cl:defun ewoc-data (node)
  "Bring-up subset of ELisp `ewoc-data'."
  (unless (elisp-ewoc-node-p node)
    (error "ELISP:EWOC-DATA expected ewoc node, got: ~S" node))
  (elisp-ewoc-node-data node))

(cl:defun ewoc-nth (ewoc n)
  "Bring-up subset of ELisp `ewoc-nth'."
  (unless (elisp-ewoc-p ewoc)
    (error "ELISP:EWOC-NTH expected ewoc, got: ~S" ewoc))
  (let* ((nodes (elisp-ewoc-nodes ewoc))
         (len (length nodes)))
    (cond
     ((null nodes) nil)
     ((minusp n) (nth (+ len n) nodes))
     (t (nth n nodes)))))

(cl:defun ewoc-next (ewoc node)
  "Bring-up subset of ELisp `ewoc-next'."
  (unless (and (elisp-ewoc-p ewoc) (elisp-ewoc-node-p node))
    (error "ELISP:EWOC-NEXT bad args: ~S ~S" ewoc node))
  (loop with seen = nil
        for n in (elisp-ewoc-nodes ewoc) do
          (cond
           (seen (return n))
           ((eq n node) (setf seen t)))
        finally
          (return nil)))

(cl:defun ewoc-prev (ewoc node)
  "Bring-up subset of ELisp `ewoc-prev'."
  (unless (and (elisp-ewoc-p ewoc) (elisp-ewoc-node-p node))
    (error "ELISP:EWOC-PREV bad args: ~S ~S" ewoc node))
  (loop with prev = nil
        for n in (elisp-ewoc-nodes ewoc) do
          (when (eq n node)
            (return prev))
          (setf prev n)
        finally
          (return nil)))

(cl:defun ewoc-location (node)
  "Bring-up subset of ELisp `ewoc-location'."
  (unless (elisp-ewoc-node-p node)
    (error "ELISP:EWOC-LOCATION expected ewoc node, got: ~S" node))
  (elisp-ewoc-node-location node))

(cl:defun ewoc-goto-node (ewoc node)
  "Bring-up subset of ELisp `ewoc-goto-node'."
  (unless (and (elisp-ewoc-p ewoc) (elisp-ewoc-node-p node))
    (error "ELISP:EWOC-GOTO-NODE bad args: ~S ~S" ewoc node))
  (with-current-buffer (elisp-ewoc-buffer ewoc)
    (goto-char (ewoc-location node)))
  nil)

(cl:defun ewoc-locate (ewoc &optional pos _guess)
  "Bring-up subset of ELisp `ewoc-locate'."
  (declare (cl:ignore _guess))
  (unless (elisp-ewoc-p ewoc)
    (error "ELISP:EWOC-LOCATE expected ewoc, got: ~S" ewoc))
  (with-current-buffer (elisp-ewoc-buffer ewoc)
    (let ((p (or pos (point)))
          (best nil))
      (dolist (node (elisp-ewoc-nodes ewoc))
        (when (<= (ewoc-location node) p)
          (setf best node)))
      (or best (car (elisp-ewoc-nodes ewoc))))))

(cl:defun ewoc-invalidate (ewoc _node &rest _ignore)
  "Bring-up subset of ELisp `ewoc-invalidate'."
  (declare (cl:ignore _node _ignore))
  (ewoc-refresh ewoc)
  nil)

(cl:defun ewoc-refresh (ewoc)
  "Bring-up subset of ELisp `ewoc-refresh'."
  (unless (elisp-ewoc-p ewoc)
    (error "ELISP:EWOC-REFRESH expected ewoc, got: ~S" ewoc))
  (with-current-buffer (elisp-ewoc-buffer ewoc)
    (erase-buffer)
    (goto-char (point-min))
    (let ((pp (elisp-ewoc-pretty-printer ewoc)))
      (insert (elisp-ewoc-header ewoc))
      (dolist (node (elisp-ewoc-nodes ewoc))
        (setf (elisp-ewoc-node-location node) (point))
        (funcall pp (ewoc-data node))
        (unless (elisp-ewoc-nosep ewoc)
          (insert #\Newline)))
      (insert (elisp-ewoc-footer ewoc))))
  nil)

(cl:defun natnump (x)
  (and (integerp x) (not (minusp x)) t))
