(in-package #:elisp)

(cl:defvar last-command-event nil)
(cl:defvar last-command nil)
(cl:defvar this-command nil)
(cl:defvar *clemacs-this-command-keys* nil)
(cl:defvar clemacs-tty-path nil)
(cl:defvar clemacs-tty-goal-column nil)

(cl:defvar *clemacs-tty-global-map* nil)
(cl:defvar *clemacs-tty-ctl-x-map* nil)

(cl:defun this-single-command-keys ()
  "Bring-up stub for ELisp `this-single-command-keys'."
  (or *clemacs-this-command-keys* (cl:make-array 0)))

(cl:defun this-command-keys ()
  "Bring-up stub for ELisp `this-command-keys'."
  (this-single-command-keys))

(cl:defun this-command-keys-vector ()
  "Bring-up stub for ELisp `this-command-keys-vector'."
  (this-single-command-keys))

(cl:defun this-single-command-raw-keys ()
  "Bring-up stub for ELisp `this-single-command-raw-keys'."
  (this-single-command-keys))

(cl:defun internal-event-symbol-parse-modifiers (type)
  "Bring-up stub for the primitive `internal-event-symbol-parse-modifiers'."
  (labels ((split (s)
             (let ((out nil)
                   (start 0))
               (loop for i from 0 to (cl:length s) do
                 (when (or (= i (cl:length s)) (cl:char= (cl:aref s i) #\-))
                   (let ((part (cl:subseq s start i)))
                     (when (> (cl:length part) 0)
                       (push part out)))
                   (setf start (1+ i))))
               (nreverse out)))
           (mod-token->mod (tok)
             (cond
              ((or (cl:string= tok "c") (cl:string= tok "ctrl") (cl:string= tok "control")) 'control)
              ((or (cl:string= tok "m") (cl:string= tok "meta")) 'meta)
              ((or (cl:string= tok "s") (cl:string= tok "shift")) 'shift)
              ((or (cl:string= tok "h") (cl:string= tok "hyper")) 'hyper)
              ((or (cl:string= tok "super")) 'super)
              ((or (cl:string= tok "alt") (cl:string= tok "a")) 'alt)
              (t nil))))
    (let* ((sym (cond
                 ((symbolp type) type)
                 ((stringp type) (cl:intern (%elisp-string->cl-string type) (cl:find-package "ELISP")))
                 (t (error "ELISP:INTERNAL-EVENT-SYMBOL-PARSE-MODIFIERS bad TYPE: ~S" type))))
           (name (cl:string-downcase (%elisp-string->cl-string (symbol-name sym))))
           (parts (split name))
           (base-name (car (last parts)))
           (mods (remove nil (cl:mapcar #'mod-token->mod (butlast parts))))
           (base (cl:intern (cl:string-upcase base-name) (cl:find-package "ELISP")))
           (els (cons base mods)))
      (put sym 'event-symbol-elements els)
      els)))

(cl:defun key-parse (keys)
  "Bring-up subset of ELisp `key-parse' (aka `kbd' syntax parsing)."
  (labels ((ws-char-p (ch)
             (or (cl:char= ch #\Space) (cl:char= ch #\Tab)
                 (cl:char= ch #\Newline) (cl:char= ch #\Page)))
           (split-hyphen (s)
             (let ((out nil)
                   (start 0))
               (loop for i from 0 to (cl:length s) do
                 (when (or (= i (cl:length s)) (cl:char= (cl:aref s i) #\-))
                   (let ((p (cl:subseq s start i)))
                     (when (> (cl:length p) 0)
                       (push p out)))
                   (setf start (1+ i))))
               (nreverse out)))
           (split-words (s)
             (let ((out nil)
                   (i 0)
                   (len (cl:length s)))
               (labels ((skip-ws ()
                          (loop while (and (< i len) (ws-char-p (cl:aref s i))) do (incf i)))
                        (read-word ()
                          (skip-ws)
                          (when (>= i len) (return-from read-word nil))
                          (let ((start i))
                            (cond
                             ((cl:char= (cl:aref s i) #\<)
                              (incf i)
                              (loop while (and (< i len) (not (cl:char= (cl:aref s i) #\>))) do (incf i))
                              (when (< i len) (incf i))
                              (cl:subseq s start i))
                             (t
                              (loop while (and (< i len) (not (ws-char-p (cl:aref s i)))) do (incf i))
                              (cl:subseq s start i))))))
                 (loop for w = (read-word) while w do (push w out)))
               (nreverse out)))
           (maybe-repetition (word)
             (let ((star (cl:position #\* word)))
               (if (and star (> star 0)
                        (cl:every #'cl:digit-char-p (cl:subseq word 0 star)))
                   (cl:values (parse-integer (cl:subseq word 0 star) :junk-allowed nil)
                              (cl:subseq word (1+ star)))
                   (cl:values 1 word))))
           (token->event (token)
             (let* ((tok (cl:string-downcase token))
                    (named (cl:assoc tok '(("nul" . 0)
                                           ("ret" . 13)
                                           ("lfd" . 10)
                                           ("tab" . 9)
                                           ("esc" . 27)
                                           ("spc" . 32)
                                           ("del" . 127))
                                     :test #'cl:string=)))
               (cond
                (named (cdr named))
                ((and (cl:search "<" tok) (cl:char= (cl:aref tok (1- (cl:length tok))) #\>))
                 ;; e.g. "<left>", "C-<left>", "C-M-<return>".
                 (let* ((lt (cl:position #\< tok))
                        (prefix (cl:subseq tok 0 lt))
                        (inner (cl:subseq tok (1+ lt) (1- (cl:length tok))))
                        (mods (split-hyphen prefix))
                        (base (cl:string-upcase inner))
                        (mods* (cl:mapcar #'cl:string-upcase mods))
                        (name (if mods*
                                  (concatenate 'string
                                               (cl:format nil "~{~A-~}" mods*)
                                               base)
                                  base)))
                   (cl:intern name (cl:find-package "ELISP"))))
                ((>= (cl:length tok) 3)
                 ;; e.g. "C-x".
                 (let* ((parts (split-hyphen tok))
                        (base (car (last parts)))
                        (mods (butlast parts)))
                   (cond
                    ((and (= (cl:length mods) 1) (cl:string= (car mods) "c") (= (cl:length base) 1))
                     (logand (cl:char-code (cl:aref base 0)) 31))
                    ((and (= (cl:length mods) 0) (= (cl:length base) 1))
                     (cl:char-code (cl:aref base 0)))
                    (t
                     ;; For non-char / multi-modifier cases, return an event symbol.
                     (cl:intern (cl:string-upcase tok) (cl:find-package "ELISP"))))))
                ((= (cl:length tok) 1)
                 (cl:char-code (cl:aref tok 0)))
                (t
                 (error "ELISP:KEY-PARSE unsupported token: ~S" token))))))
    (cond
     ((vectorp keys) keys)
     ((null keys) (cl:make-array 0))
     ((stringp keys)
      (let* ((s (%elisp-string->cl-string keys))
             (words (split-words s))
             (events nil))
        (dolist (w words)
          (multiple-value-bind (times body) (maybe-repetition w)
            (dotimes (_ times)
              (push (token->event body) events))))
        (coerce (nreverse events) 'vector)))
     (t
      (error "ELISP:KEY-PARSE expected string or vector, got: ~S" keys)))))

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
  (setf last-command this-command)
  (setf this-command command)
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
            (setf *clemacs-this-command-keys* seq)
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

(cl:defun self-insert-command (&optional n)
  "Bring-up subset of ELisp `self-insert-command'."
  (dotimes (_ (or n 1))
    (clemacs-tty-self-insert-command))
  nil)

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

  (let* ((global
          (let ((g (current-global-map)))
            (if (and g (keymapp g)) g nil)))
         (ctl-x
          (cond
           ((and (boundp 'ctl-x-map) (keymapp (symbol-value 'ctl-x-map)))
            (symbol-value 'ctl-x-map))
           ((and (boundp 'ctl-x-map) (keymapp 'ctl-x-map))
            'ctl-x-map)
           (t nil))))
    ;; If we don't have the shipped keymaps yet (e.g. `startup.editor-core.files`
    ;; wasn't loaded), fall back to a minimal bring-up global map.
    (when (null global)
      (when (or (null *clemacs-tty-global-map*) (not (keymapp *clemacs-tty-global-map*)))
        (setf *clemacs-tty-global-map* (make-sparse-keymap)))
      (setf global *clemacs-tty-global-map*)
      (use-global-map global))

    (when (null ctl-x)
      (when (or (null *clemacs-tty-ctl-x-map*) (not (keymapp *clemacs-tty-ctl-x-map*)))
        (setf *clemacs-tty-ctl-x-map* (make-sparse-keymap)))
      (setf ctl-x *clemacs-tty-ctl-x-map*)
      (define-key global (vector 24) ctl-x))

    ;; C-x ...
    (define-key ctl-x (vector 19) 'clemacs-tty-save-buffer) ; C-x C-s
    (define-key ctl-x (vector 3) 'clemacs-tty-quit)          ; C-x C-c

    ;; Movement.
    (define-key global 'left 'clemacs-tty-backward-char)
    (define-key global 'right 'clemacs-tty-forward-char)
    (define-key global 'up 'clemacs-tty-previous-line)
    (define-key global 'down 'clemacs-tty-next-line)

    ;; Traditional TTY keys.
    (define-key global (vector 2) 'clemacs-tty-backward-char) ; C-b
    (define-key global (vector 6) 'clemacs-tty-forward-char)  ; C-f
    (define-key global (vector 16) 'clemacs-tty-previous-line) ; C-p
    (define-key global (vector 14) 'clemacs-tty-next-line)      ; C-n

    ;; Editing (keep these explicit until the shipped bindings are loaded deeper).
    (define-key global (vector 127) 'clemacs-tty-delete-backward-char) ; DEL
    (define-key global (vector 13) 'clemacs-tty-newline)               ; RET

    ;; Default (only for the bring-up map; avoid poisoning the shipped global map).
    (when (eq global *clemacs-tty-global-map*)
      (define-key global t 'clemacs-tty-self-insert-command))

    t))
