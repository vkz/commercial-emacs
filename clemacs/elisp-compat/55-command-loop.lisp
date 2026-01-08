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
	           (named-token-code (tok)
	             (let ((lc (cl:string-downcase tok)))
	               (cdr (cl:assoc lc '(("nul" . 0)
	                                   ("ret" . 13)
	                                   ("lfd" . 10)
	                                   ("tab" . 9)
	                                   ("esc" . 27)
	                                   ("spc" . 32)
	                                   ("del" . 127))
	                             :test #'cl:string=))))
	           (mod-token->keyword (tok)
	             (cond
	              ;; One-letter modifiers are case sensitive for S (shift) vs s (super).
	              ((or (cl:string= tok "C")
	                   (cl:string= tok "c")
	                   (cl:string-equal tok "ctrl")
	                   (cl:string-equal tok "control"))
	               :control)
	              ((or (cl:string= tok "M")
	                   (cl:string= tok "m")
	                   (cl:string-equal tok "meta"))
	               :meta)
	              ((or (cl:string= tok "S")
	                   (cl:string-equal tok "shift"))
	               :shift)
	              ((or (cl:string= tok "s")
	                   (cl:string-equal tok "super"))
	               :super)
	              ((or (cl:string= tok "H")
	                   (cl:string= tok "h")
	                   (cl:string-equal tok "hyper"))
	               :hyper)
	              ((or (cl:string= tok "A")
	                   (cl:string= tok "a")
	                   (cl:string-equal tok "alt"))
	               :alt)
	              (t nil)))
	           (mod->prefix-token (m)
	             (case m
	               (:control "C")
	               (:meta "M")
	               (:shift "S")
	               (:super "s")
	               (:hyper "H")
	               (:alt "A")
	               (otherwise (error "ELISP:KEY-PARSE unknown modifier keyword: ~S" m))))
	           (caret-control-code (tok)
	             (when (and (= (cl:length tok) 2) (cl:char= (cl:aref tok 0) #\^))
	               (let ((ch (cl:aref tok 1)))
	                 (if (cl:char= ch #\?)
	                     127
	                     (logand (cl:char-code ch) #x1f)))))
	           (octal-escape-code (tok)
	             (when (and (>= (cl:length tok) 2) (cl:char= (cl:aref tok 0) #\\))
	               (let ((digits (cl:subseq tok 1)))
	                 (when (and (<= 1 (cl:length digits) 3)
	                            (cl:every #'cl:digit-char-p digits)
	                            (cl:every (lambda (d) (digit-char-p d 8)) digits))
	                   (parse-integer digits :radix 8 :junk-allowed nil)))))
	           (apply-char-modifiers (code mods &key (controlify-allowed t))
	             (let ((bits 0)
	                   (ctlp nil))
	               (dolist (m mods)
	                 (case m
	                   (:alt (incf bits +char-alt+))
	                   (:super (incf bits +char-super+))
	                   (:hyper (incf bits +char-hyper+))
	                   (:shift (incf bits +char-shift+))
	                   (:meta (incf bits +char-meta+))
	                   (:control (setf ctlp t))
	                   (otherwise (error "ELISP:KEY-PARSE unknown modifier keyword: ~S" m))))
	               (let ((ctl-code (and ctlp controlify-allowed (%controlify-ascii code))))
	                 (cond
	                  ((and ctlp (= code 0))
	                   (+ bits +char-ctl+))
	                  (ctl-code
	                   (+ bits ctl-code))
	                  (ctlp
	                   (+ bits +char-ctl+ code))
	                  (t
	                   (+ bits code))))))
	           (mods->event-symbol (mods base-name)
	             (let* ((prefixes (cl:mapcar #'mod->prefix-token mods))
	                    (name
	                      (if prefixes
	                          (cl:concatenate 'cl:string
	                                          (cl:format nil "~{~A-~}" prefixes)
	                                          base-name)
	                          base-name)))
	               (cl:intern (cl:string-upcase name) (cl:find-package "ELISP"))))
	           (token->event (token)
	             (let* ((len (cl:length token))
	                    (lt (cl:position #\< token))
	                    (anglep (and lt (> len 0) (cl:char= (cl:aref token (1- len)) #\>)))
	                    (mods-parts nil)
	                    (base-part nil)
	                    (base-from-named nil)
	                    (base-from-angle nil))
	               (cond
	                ;; Old-style control notation (from key-description).
	                ((and (not anglep) (null lt))
	                 (let ((cc (caret-control-code token)))
	                   (when cc
	                     (return-from token->event cc)))
	                 (let ((oc (octal-escape-code token)))
	                   (when oc
	                     (return-from token->event oc))))
	                (t nil))

	               (if anglep
	                   (let* ((prefix (cl:subseq token 0 lt))
	                          (inner (cl:subseq token (1+ lt) (1- len)))
	                          (inner-parts (split-hyphen inner)))
	                     (setf mods-parts (append (split-hyphen prefix) (butlast inner-parts))
	                           base-part (car (last inner-parts))
	                           base-from-angle t))
	                   (let* ((parts (split-hyphen token)))
	                     (setf mods-parts (butlast parts)
	                           base-part (car (last parts)))))

	               (when (or (null base-part) (= (cl:length base-part) 0))
	                 (error "ELISP:KEY-PARSE invalid token (missing base): ~S" token))

	               (let ((mods nil))
	                 (dolist (p mods-parts)
	                   (let ((m (mod-token->keyword p)))
	                     (when (null m)
	                       (error "ELISP:KEY-PARSE unknown modifier ~S in token ~S" p token))
	                     (push m mods)))
	                 (setf mods (nreverse mods))

	                 (let* ((named (named-token-code base-part))
	                        (base-is-char nil)
	                        (base-code nil)
	                        (controlify-allowed nil))
	                   (cond
	                    (named
	                     (setf base-is-char t
	                           base-code named
	                           base-from-named t
	                           controlify-allowed nil))
	                    ((= (cl:length base-part) 1)
	                     (setf base-is-char t
	                           base-code (cl:char-code (cl:aref base-part 0))
	                           controlify-allowed t))
	                    (base-from-angle
	                     ;; In <> syntax, treat multi-char base names as event symbols.
	                     (return-from token->event (mods->event-symbol mods base-part)))
	                    ((null mods)
	                     ;; Bare multi-char tokens are handled elsewhere (or are named tokens above).
	                     (error "ELISP:KEY-PARSE unsupported token: ~S" token))
	                    (t
	                     ;; Reject modifier forms like "C-xx" and "M-x<TAB>".
	                     (error "ELISP:KEY-PARSE invalid modified token: ~S" token)))

	                   (when (and base-is-char (not base-from-named) (not base-from-angle))
	                     (setf controlify-allowed t))
	                   (when (and base-is-char base-from-angle)
	                     (setf controlify-allowed nil))

	                   (apply-char-modifiers base-code mods
	                                         :controlify-allowed (and controlify-allowed (not base-from-named))))))))

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
	              (let ((body-lc (cl:string-downcase body)))
	                ;; For bare key sequences like "foobar" (no spaces), treat the
	                ;; token as a run of literal characters, unless it is a named
	                ;; key like "RET" or includes modifiers/<> syntax.
	                (cond
	                 ((and (> (cl:length body) 2)
	                       (cl:char= (cl:aref body 0) #\<)
	                       (cl:char= (cl:aref body (1- (cl:length body))) #\>)
	                       (let ((inner (cl:subseq body 1 (1- (cl:length body)))))
	                         (find-if #'ws-char-p inner)))
	                  ;; Treat "< right >" as the literal string "<right>".
	                  ;; We accumulate EVENTS with PUSH (then NREVERSE), so push
	                  ;; characters in forward order here.
	                  (push (cl:char-code #\<) events)
	                  (let ((inner (cl:subseq body 1 (1- (cl:length body)))))
	                    (loop for ch across inner
	                          unless (ws-char-p ch) do (push (cl:char-code ch) events)))
	                  (push (cl:char-code #\>) events))
	                 ((and (> (cl:length body) 1)
	                       (null (cl:position #\- body))
	                       (null (cl:position #\< body))
	                       (null (named-token-code body-lc))
	                       (null (caret-control-code body))
	                       (null (octal-escape-code body)))
	                  (dotimes (i (cl:length body))
	                    (push (cl:char-code (cl:aref body i)) events)))
	                 (t
	                  (push (token->event body) events)))))))
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
