(in-package #:elisp)

(cl:defvar last-command-event nil)
(cl:defvar clemacs-tty-path nil)
(cl:defvar clemacs-tty-goal-column nil)

(cl:defvar *clemacs-tty-global-map* nil)
(cl:defvar *clemacs-tty-ctl-x-map* nil)

(cl:defun key-binding (keys &optional accept-default _no-remap _position)
  "Bring-up subset of ELisp `key-binding'."
  (declare (cl:ignore _no-remap _position))
  (let* ((local (current-local-map))
         (global (current-global-map)))
    (cond
     ((and local (lookup-key local keys accept-default)))
     ((and global (lookup-key global keys accept-default)))
     (t nil))))

(cl:defun command-execute (command &optional _record-flag _keys _special)
  "Bring-up subset of ELisp `command-execute'."
  (declare (cl:ignore _record-flag _keys _special))
  (when (null command)
    (return-from command-execute nil))
  ;; During bring-up we treat \"commands\" as simply callable function
  ;; designators, and ignore interactive specs/prefix args/etc.
  (funcall command))

(cl:defun read-key-sequence (&optional _prompt &rest _args)
  "Bring-up subset of ELisp `read-key-sequence'.

Returns a vector of events."
  (declare (cl:ignore _prompt _args))
  (let ((events nil))
    (loop
      (let ((ev (clemacs::%tty-read-event)))
        (setf last-command-event ev)
        (push ev events)
        (let* ((seq (coerce (nreverse events) 'vector))
               (binding (key-binding seq t)))
          (when (or (null binding) (not (keymapp binding)))
            (return seq)))))))

(cl:defun clemacs-tty--reset-goal-column ()
  (setf clemacs-tty-goal-column nil)
  nil)

(cl:defun clemacs-tty-self-insert-command ()
  (clemacs-tty--reset-goal-column)
  (cond
   ((integerp last-command-event)
    (insert (string last-command-event))
    nil)
   (t
    (cl:format *error-output* "[clemacs] tty self-insert: bad event: ~S~%" last-command-event)
    (finish-output *error-output*)
    nil)))

(cl:defun clemacs-tty-backward-char (&optional n)
  (backward-char (or n 1))
  (clemacs-tty--reset-goal-column)
  nil)

(cl:defun clemacs-tty-forward-char (&optional n)
  (forward-char (or n 1))
  (clemacs-tty--reset-goal-column)
  nil)

(cl:defun clemacs-tty--move-to-column (target)
  (let ((col (max 0 (or target 0)))
        (cur 0))
    (beginning-of-line)
    (loop while (and (< cur col) (not (eolp))) do
      (let ((c (char-after)))
        (cond
         ((null c) (return))
         ((= c (char-code #\Tab))
          (incf cur (- tab-width (mod cur tab-width))))
         (t
          (incf cur 1))))
      (forward-char 1)))
  nil)

(cl:defun clemacs-tty-next-line (&optional n)
  (let* ((steps (or n 1))
         (goal (or clemacs-tty-goal-column (current-column))))
    (setf clemacs-tty-goal-column goal)
    (forward-line steps)
    (clemacs-tty--move-to-column goal))
  nil)

(cl:defun clemacs-tty-previous-line (&optional n)
  (clemacs-tty-next-line (- (or n 1))))

(cl:defun clemacs-tty-delete-backward-char (&optional n)
  (delete-char (- (or n 1)))
  (clemacs-tty--reset-goal-column)
  nil)

(cl:defun clemacs-tty-newline (&optional n)
  (dotimes (_ (or n 1))
    (insert (string (char-code #\Newline))))
  (clemacs-tty--reset-goal-column)
  nil)

(cl:defun clemacs-tty--ensure-path ()
  (when (and clemacs-tty-path (stringp clemacs-tty-path)
             (not (cl:string= (%elisp-string->cl-string clemacs-tty-path) "")))
    (return-from clemacs-tty--ensure-path clemacs-tty-path))
  (let ((p (clemacs::%tty-prompt "Save as: ")))
    (when (and p (stringp p) (not (cl:string= p "")))
      (setf clemacs-tty-path p)
      clemacs-tty-path)))

(cl:defun clemacs-tty-save-buffer ()
  (let ((p (clemacs-tty--ensure-path)))
    (unless p
      (clemacs::tty-write-string "\a")
      (return-from clemacs-tty-save-buffer nil))
    (write-region (point-min) (point-max) p nil)
    (set-buffer-modified-p nil)
    t))

(cl:defun clemacs-tty-quit ()
  (cl:error 'clemacs:clemacs-quit))

(cl:defun clemacs-tty-setup (&key path)
  (setf clemacs-tty-path (and path (not (cl:string= path "")) path))

  (when (or (null *clemacs-tty-global-map*) (not (keymapp *clemacs-tty-global-map*)))
    (setf *clemacs-tty-global-map* (make-sparse-keymap)))
  (when (or (null *clemacs-tty-ctl-x-map*) (not (keymapp *clemacs-tty-ctl-x-map*)))
    (setf *clemacs-tty-ctl-x-map* (make-sparse-keymap)))

  (use-global-map *clemacs-tty-global-map*)

  ;; Prefixes.
  (define-key *clemacs-tty-global-map* (vector 24) *clemacs-tty-ctl-x-map*)

  ;; C-x ...
  (define-key *clemacs-tty-ctl-x-map* (vector 19) 'clemacs-tty-save-buffer) ; C-x C-s
  (define-key *clemacs-tty-ctl-x-map* (vector 3) 'clemacs-tty-quit)          ; C-x C-c

  ;; Movement.
  (define-key *clemacs-tty-global-map* 'left 'clemacs-tty-backward-char)
  (define-key *clemacs-tty-global-map* 'right 'clemacs-tty-forward-char)
  (define-key *clemacs-tty-global-map* 'up 'clemacs-tty-previous-line)
  (define-key *clemacs-tty-global-map* 'down 'clemacs-tty-next-line)

  ;; Traditional TTY keys.
  (define-key *clemacs-tty-global-map* (vector 2) 'clemacs-tty-backward-char) ; C-b
  (define-key *clemacs-tty-global-map* (vector 6) 'clemacs-tty-forward-char)  ; C-f
  (define-key *clemacs-tty-global-map* (vector 16) 'clemacs-tty-previous-line) ; C-p
  (define-key *clemacs-tty-global-map* (vector 14) 'clemacs-tty-next-line)      ; C-n

  ;; Editing.
  (define-key *clemacs-tty-global-map* (vector 127) 'clemacs-tty-delete-backward-char) ; DEL
  (define-key *clemacs-tty-global-map* (vector 13) 'clemacs-tty-newline)               ; RET

  ;; Default.
  (define-key *clemacs-tty-global-map* t 'clemacs-tty-self-insert-command)

  t)
