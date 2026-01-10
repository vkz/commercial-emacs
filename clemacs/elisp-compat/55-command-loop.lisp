(in-package #:elisp)

(cl:defvar last-command-event nil)
(cl:defvar last-command nil)
(cl:defvar this-command nil)
(cl:defvar *clemacs-this-command-keys* nil)
(cl:defvar overriding-local-map nil)
(cl:defvar overriding-terminal-local-map nil)
(cl:defvar clemacs-tty-path nil)
(cl:defvar clemacs-tty-goal-column nil)
(cl:defvar *clemacs-minibuffer-depth* 0)
(cl:defvar *clemacs-last-minibuffer-contents* (string-to-unibyte ""))

(cl:defun clemacs--ensure-minibuffer-buffer ()
  (or (and (boundp '*clemacs-minibuffer-buffer*) (bufferp *clemacs-minibuffer-buffer*)
           *clemacs-minibuffer-buffer*)
      (setf *clemacs-minibuffer-buffer* (get-buffer-create +clemacs-minibuffer-buffer-name+))))

(cl:defvar *clemacs-tty-global-map* nil)
(cl:defvar *clemacs-tty-ctl-x-map* nil)

(cl:defun minibuffer-depth ()
  "Bring-up subset of the C primitive `minibuffer-depth'."
  (or *clemacs-minibuffer-depth* 0))

(cl:defun minibuffer-contents ()
  "Bring-up subset of the C primitive `minibuffer-contents' (TTY prompt).

When clemacs is in a `read-from-minibuffer' call, we model the minibuffer as an
ordinary buffer (`*Minibuf-0*`) containing PROMPT followed by the current input.
Outside the minibuffer, we return the last captured minibuffer input."
  (cond
   ((and *clemacs-minibuffer-active-p* (bufferp (clemacs--ensure-minibuffer-buffer)))
    (with-current-buffer (clemacs--ensure-minibuffer-buffer)
      (buffer-substring-no-properties
       (or *clemacs-minibuffer-prompt-end* (point-min))
       (point-max))))
   (t (or *clemacs-last-minibuffer-contents* (string-to-unibyte "")))))

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

(cl:defun set--this-command-keys (&rest args)
  "Bring-up stub for ELisp internal `set--this-command-keys'."
  (setf *clemacs-this-command-keys* (and args (first args)))
  nil)

(cl:defun %clemacs--unread-pop ()
  (when (consp unread-command-events)
    (let ((ev (car unread-command-events)))
      (setf unread-command-events (cdr unread-command-events))
      ev)))

(cl:defun %clemacs--unread-push (ev)
  (setf unread-command-events (cons ev (or unread-command-events nil)))
  nil)

(cl:defun input-pending-p ()
  "Bring-up stub for the C primitive `input-pending-p'."
  nil)

(cl:defun discard-input ()
  "Bring-up stub for the C primitive `discard-input'."
  nil)

(cl:defun command-remapping (_command &optional _position _keymaps)
  "Bring-up stub for the C primitive `command-remapping'."
  (declare (cl:ignore _command _position _keymaps))
  nil)

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

(cl:defun local-key-binding (keys &optional accept-default)
  "Bring-up subset of ELisp `local-key-binding'."
  (let ((local (current-local-map)))
    (and local (lookup-key local keys accept-default))))

(cl:defun global-key-binding (keys &optional accept-default)
  "Bring-up subset of ELisp `global-key-binding'."
  (let ((global (current-global-map)))
    (and global (lookup-key global keys accept-default))))

(cl:defun interactive-form (function)
  "Bring-up subset of ELisp `interactive-form'."
  (labels ((function-name-symbol (fn)
             (cond
              ((symbolp fn) fn)
              ((and (consp fn) (eq (car fn) 'macro))
               (function-name-symbol (cdr fn)))
              ((and (consp fn) (eq (car fn) 'autoload))
               nil)
              ((functionp fn)
               (multiple-value-bind (_lambda _closed name)
                   (cl:function-lambda-expression fn)
                 (declare (cl:ignore _lambda _closed))
                 (and (symbolp name) name)))
              (t nil)))

           (skip-decls-and-doc (body)
             (let ((b body))
               (when (and (consp b) (stringp (car b)))
                 (setf b (cdr b)))
               (loop while (and (consp b)
                                (consp (car b))
                                (eq (caar b) 'declare))
                     do (setf b (cdr b)))
               b))

           (scan-interactive (forms)
             (dolist (f forms nil)
               (when (and (consp f) (eq (car f) 'interactive))
                 (return f))))

           (interactive-form-from-lambda (lambda-expr)
             (when (and (consp lambda-expr) (eq (car lambda-expr) 'lambda))
               (let ((body (skip-decls-and-doc (cddr lambda-expr))))
                 (or (scan-interactive body)
                     ;; Many functions are compiled/normalized into a single
                     ;; BLOCK; look for an `(interactive ...)' form inside it.
                     (when (and (consp body)
                                (consp (car body))
                                (eq (caar body) 'block))
                       (let ((block-body (cddr (car body))))
                         (scan-interactive (skip-decls-and-doc block-body))))))))

           (lambda-expression-for (fn)
             (cond
              ((and (consp fn) (eq (car fn) 'lambda)) fn)
              ((functionp fn)
               (multiple-value-bind (lambda-expr _closed _name)
                   (cl:function-lambda-expression fn)
                 (declare (cl:ignore _closed _name))
                 lambda-expr))
              (t nil))))
    (let* ((sym (function-name-symbol function))
           (iform (and sym (function-get sym 'interactive-form))))
      (cond
       (iform iform)
       (t
        (let* ((fn (cond
                    ((and (symbolp sym) (fboundp sym)) (symbol-function sym))
                    (t function)))
               (lambda-expr (lambda-expression-for fn)))
          (and lambda-expr (interactive-form-from-lambda lambda-expr))))))))

(cl:defun commandp (function &optional _for-call-interactively)
  "Bring-up subset of ELisp `commandp'."
  (declare (cl:ignore _for-call-interactively))
  (and (interactive-form function) t))

(cl:defun call-interactively (command &optional _record-flag _keys)
  "Bring-up subset of ELisp `call-interactively'."
  (declare (cl:ignore _record-flag _keys))
  (let* ((iform (interactive-form command))
         (spec (and (consp iform) (eq (car iform) 'interactive) (cadr iform))))
    (labels ((split-lines (s)
               (let ((out nil)
                     (start 0)
                     (len (cl:length s)))
                 (loop for i from 0 to len do
                   (when (or (= i len) (cl:char= (cl:aref s i) #\Newline))
                     (push (cl:subseq s start i) out)
                     (setf start (1+ i))))
                 (nreverse out)))
             (parse-spec-string (spec-string)
               ;; Return a list of args (or signal an error).
               (let ((args nil))
                 (dolist (line (split-lines spec-string))
                   (when (> (cl:length line) 0)
                     (let* ((i 0)
                            (len (cl:length line)))
                       ;; Prefix chars.  For now, only * is meaningful (read-only check).
                       (loop while (< i len) do
                         (let ((ch (cl:aref line i)))
                           (cond
                            ((cl:char= ch #\*)
                             (when (fboundp 'barf-if-buffer-read-only)
                               (barf-if-buffer-read-only))
                             (incf i))
                            ((or (cl:char= ch #\@) (cl:char= ch #\^))
                             (incf i))
                            (t (return)))))
                       (when (< i len)
                         (let* ((code (cl:aref line i))
                                (prompt (cl:subseq line (1+ i))))
                           (case code
                             (#\p
                              (push (prefix-numeric-value current-prefix-arg) args))
                             (#\P
                              (push current-prefix-arg args))
                             (#\s
                              (push (read-from-minibuffer (string-to-unibyte prompt)) args))
                             (#\b
                              ;; `interactive "b"` yields a buffer name string.
                              (push (read-from-minibuffer (string-to-unibyte prompt)) args))
                             (#\f
                              (push (read-file-name (string-to-unibyte prompt)) args))
                             (#\F
                              (push (read-file-name (string-to-unibyte prompt)) args))
                             (#\r
                              (push (region-beginning) args)
                              (push (region-end) args))
                             (otherwise
                              (error "ELISP:CALL-INTERACTIVELY unsupported interactive code: ~S"
                                     (string code)))))))))
                 (nreverse args))))
      (cond
       ((and (stringp spec)
             (not (cl:string= (%elisp-string->cl-string spec) "")))
        (let ((args (parse-spec-string (%elisp-string->cl-string spec))))
          (apply command args)))
       ((consp spec)
        ;; Emacs allows `(interactive (list ...))` forms.  Bring-up subset:
        ;; evaluate SPEC and treat the result as an arg list.
        (let ((args (eval spec)))
          (cond
           ((null args) (funcall command))
           ((listp args) (apply command args))
           (t (funcall command args)))))
       (t
        (funcall command))))))

(cl:defun command-execute (command &optional _record-flag _keys _special)
  "Bring-up subset of ELisp `command-execute'."
  (declare (cl:ignore _record-flag _keys _special))
  (when (null command)
    (return-from command-execute nil))
  (setf last-command this-command)
  (setf this-command command)
  (let ((saved-prefix-arg prefix-arg))
    ;; Emacs command loop behavior: `prefix-arg' is for the *next* command.
    ;; Promote it to `current-prefix-arg' at dispatch, then clear it.
    (setf prefix-arg nil)
    (setf current-prefix-arg saved-prefix-arg)
    (unwind-protect
        (call-interactively command)
      (setf current-prefix-arg nil))))

(cl:defun read-event (&optional _prompt _inherit-input-method _seconds)
  "Bring-up subset of ELisp `read-event'.

Returns a single event: an integer character code or an ELISP symbol
(LEFT/RIGHT/UP/DOWN)."
  (declare (cl:ignore _prompt _inherit-input-method _seconds))
  (let ((ev (or (%clemacs--unread-pop)
                (clemacs::%tty-read-event))))
    (setf last-command-event ev)
    ev))

(cl:defun event-apply-modifier (event symbol _lshiftby _prefix)
  "Bring-up subset of the C primitive `event-apply-modifier'."
  (declare (cl:ignore _lshiftby _prefix))
  (cond
   ((and (integerp event) (symbolp symbol) (eq symbol 'control))
    (logand event #x1F))
   (t event)))

(cl:defun single-key-description (key &optional _no-angles)
  "Bring-up subset of the C primitive `single-key-description'."
  (declare (cl:ignore _no-angles))
  (cond
   ((integerp key)
    (let ((s
            (cond
             ((and (<= 1 key) (<= key 26))
              (cl:format nil "C-~A" (code-char (+ key 96))))
             ((= key 27) "ESC")
             ((= key 127) "DEL")
             (t
              (let ((ch (ignore-errors (code-char key))))
                (if ch (string ch) (cl:format nil "#<key ~D>" key)))))))
      s))
   ((symbolp key)
    (string-to-multibyte (symbol-name key)))
   (t
    (prin1-to-string key))))

(cl:defmacro minibuffer-with-setup-hook (hook &body body)
  "Bring-up subset of ELisp `minibuffer-with-setup-hook'.

This only extends `minibuffer-setup-hook' around BODY."
  (let ((saved (cl:gensym "SAVED-MINIBUFFER-SETUP-HOOK-")))
    `(let ((,saved (and (boundp 'minibuffer-setup-hook)
                        (symbol-value 'minibuffer-setup-hook))))
       (unwind-protect
           (progn
             (set 'minibuffer-setup-hook
                  (cons ,hook (or ,saved nil)))
             ,@body)
         (set 'minibuffer-setup-hook ,saved)))))

(cl:defvar *clemacs-minibuffer-local-map* nil)

(cl:defun keyboard-quit ()
  "Bring-up subset of ELisp `keyboard-quit'."
  (signal 'quit nil))

(cl:defun clemacs--minibuffer--prompt-end ()
  (or (and (boundp '*clemacs-minibuffer-prompt-end*)
           (integerp *clemacs-minibuffer-prompt-end*)
           *clemacs-minibuffer-prompt-end*)
      (point-min)))

(cl:defun clemacs--minibuffer--ensure-point-after-prompt ()
  (let ((pe (clemacs--minibuffer--prompt-end)))
    (when (< (point) pe)
      (goto-char pe)))
  nil)

(cl:defun clemacs-minibuffer-self-insert-command (&optional n)
  "Bring-up minibuffer self-insert command (prompt-safe)."
  (clemacs--minibuffer--ensure-point-after-prompt)
  (self-insert-command n))

(cl:defun clemacs-minibuffer-backward-char (&optional n)
  "Bring-up minibuffer backward-char (prompt-safe)."
  (clemacs--minibuffer--ensure-point-after-prompt)
  (let ((pe (clemacs--minibuffer--prompt-end)))
    (backward-char (or n 1))
    (when (< (point) pe)
      (goto-char pe)))
  nil)

(cl:defun clemacs-minibuffer-forward-char (&optional n)
  "Bring-up minibuffer forward-char (prompt-safe)."
  (clemacs--minibuffer--ensure-point-after-prompt)
  (forward-char (or n 1))
  nil)

(cl:defun clemacs-minibuffer-delete-backward-char (&optional n)
  "Bring-up minibuffer delete-backward-char (prompt-safe)."
  (clemacs--minibuffer--ensure-point-after-prompt)
  (let ((pe (clemacs--minibuffer--prompt-end))
        (count (or n 1)))
    (dotimes (_ count)
      (when (> (point) pe)
        (delete-char -1))))
  nil)

(cl:defun clemacs--ensure-minibuffer-local-map ()
  (let* ((m
           (cond
            ((and *clemacs-minibuffer-local-map*
                  (keymapp *clemacs-minibuffer-local-map*))
             *clemacs-minibuffer-local-map*)
            ((and (boundp 'minibuffer-local-map)
                  (keymapp (symbol-value 'minibuffer-local-map)))
             (symbol-value 'minibuffer-local-map))
            (t (make-sparse-keymap)))))
    ;; Bring-up invariant: `minibuffer-local-map' must be usable in a TTY-only
    ;; session even when we are not loading `lisp/minibuffer.el`.
    (labels ((ensure (key def)
               (when (null (ignore-errors (lookup-key m key nil)))
                 (define-key m key def))))
      ;; Exit/abort.
      (ensure (vector 13) 'exit-minibuffer)     ; RET
      (ensure (vector 7) 'keyboard-quit)        ; C-g

      ;; Editing.
      (ensure (vector 127) 'clemacs-minibuffer-delete-backward-char) ; DEL

      ;; Movement (arrows + C-b/C-f).
      (ensure 'left 'clemacs-minibuffer-backward-char)
      (ensure 'right 'clemacs-minibuffer-forward-char)
      (ensure (vector 2) 'clemacs-minibuffer-backward-char) ; C-b
      (ensure (vector 6) 'clemacs-minibuffer-forward-char)  ; C-f

      ;; Default.
      (ensure t 'clemacs-minibuffer-self-insert-command))

    (setf *clemacs-minibuffer-local-map* m)
    (set 'minibuffer-local-map m)
    m))

(cl:defun read-from-minibuffer (prompt &optional _initial-contents _keymap _read
                                       _hist _default-value _inherit-input-method)
  "Bring-up subset of the C primitive `read-from-minibuffer'.

In clemacs TTY bring-up, the minibuffer is modeled as an ordinary buffer
(`*Minibuf-0*`) containing PROMPT followed by editable input text. This is
intentionally small but Emacs-shaped enough for core completion/help paths."
  (declare (cl:ignore _read _hist _inherit-input-method))
  (unless (stringp prompt)
    (error "ELISP:READ-FROM-MINIBUFFER expected string PROMPT, got: ~S" prompt))
  (let* ((mbuf (clemacs--ensure-minibuffer-buffer))
         (prompt-end nil)
         (saved-mbuf-local-map (with-current-buffer mbuf (current-local-map)))
         (keymap (if (and _keymap (keymapp _keymap))
                     _keymap
                     (clemacs--ensure-minibuffer-local-map)))
         (result nil))
    (unwind-protect
        (progn
          (setf *clemacs-minibuffer-active-p* t
                *clemacs-minibuffer-selected-window* (selected-window))
          (with-current-buffer mbuf
            (erase-buffer)
            (insert prompt)
            (setf prompt-end (point))
            (setf *clemacs-minibuffer-prompt-end* prompt-end)
            (use-local-map keymap)
            (when (and _initial-contents (stringp _initial-contents))
              (insert _initial-contents))
            (goto-char (point-max)))
          (let ((*clemacs-minibuffer-depth* (1+ (minibuffer-depth))))
            ;; Run setup hooks if present (common callers rely on it for keymaps).
            (with-current-buffer mbuf
              (when (and (boundp 'minibuffer-setup-hook)
                         (consp (symbol-value 'minibuffer-setup-hook)))
                (dolist (fn (symbol-value 'minibuffer-setup-hook))
                  (when (functionp fn)
                    (ignore-errors (funcall fn))))))
            (cond
             (noninteractive
              (setf result
                    (cond
                     ((and _initial-contents (stringp _initial-contents)) _initial-contents)
                     ((and _default-value (stringp _default-value)) _default-value)
                     (t (string-to-unibyte ""))))
              (with-current-buffer mbuf
                (delete-region (or prompt-end (point-min)) (point-max))
                (goto-char (point-max))
                (insert result))
              (setf *clemacs-last-minibuffer-contents* result))
             (t
              (setf result
                    (cl:catch +clemacs-minibuffer-exit-tag+
                      (loop
                        (with-current-buffer mbuf
                          (clemacs--minibuffer--ensure-point-after-prompt)
                          (let* ((keys (read-key-sequence nil))
                                 (cmd (key-binding keys t)))
                            (cond
                             ((and cmd (not (integerp cmd)) (not (keymapp cmd)))
                              (command-execute cmd))
                             (t (ding))))))))
              (setf *clemacs-last-minibuffer-contents* result)))))
      (setf *clemacs-minibuffer-active-p* nil
            *clemacs-minibuffer-selected-window* nil)
      (with-current-buffer mbuf
        (use-local-map saved-mbuf-local-map)))
    result))

(cl:defun completing-read (prompt collection &optional predicate require-match
                                  _initial-input _hist def _inherit-input-method)
  "Bring-up subset of the C primitive `completing-read'.

This is intentionally small, but Emacs-shaped enough to unblock many callers.
Supported COLLECTION forms:
- list of strings
- list of (STRING . VALUE) pairs (we complete over STRING keys)

If `noninteractive' is non-nil, prefer DEF (or error if REQUIRE-MATCH is set and
no default is provided)."
  (declare (cl:ignore _initial-input _hist _inherit-input-method))
  (unless (stringp prompt)
    (error "ELISP:COMPLETING-READ expected string PROMPT, got: ~S" prompt))
  (labels ((default-string ()
             (cond
              ((null def) nil)
              ((stringp def) def)
              ((and (consp def) (stringp (car def))) (car def))
              (t nil)))
           (collection-strings ()
             (cond
              ;; Simple list/alist collections.
              ((listp collection)
               (let ((out nil))
                 (dolist (x collection)
                   (cond
                    ((stringp x) (push x out))
                    ((and (consp x) (stringp (car x))) (push (car x) out))
                    (t nil)))
                 (nreverse out)))
              ;; Obarray-style collections (used by `execute-extended-command`).
              (t
               (let ((pred (and predicate (functionp predicate)))
                     (out nil))
                 (mapatoms
                  (lambda (sym)
                    (when (and (symbolp sym)
                               (or (null pred)
                                   (ignore-errors (funcall predicate sym))))
                      (let ((n (ignore-errors (symbol-name sym))))
                        (when (stringp n)
                          (push n out))))))
                 (nreverse out)))))
           (exact-member-p (s cands)
             (and (stringp s)
                  (cl:member (%elisp-string->cl-string s) cands
                             :test #'cl:string=
                             :key (lambda (x) (%elisp-string->cl-string x)))))
           (unique-completion (input cands)
             (let ((matches (all-completions input cands)))
               (when (= (length matches) 1)
                 (first matches)))))
    (let* ((cands (collection-strings))
           (d (default-string)))
      (when noninteractive
        (return-from completing-read
          (cond
           (d d)
           (require-match
            (let ((only (and (= (length cands) 1) (first cands))))
              (or only
                  (error "ELISP:COMPLETING-READ noninteractive needs DEF when REQUIRE-MATCH"))))
           (t (or d (string-to-unibyte ""))))))
      (let* ((prompt* (if d
                          (string-to-unibyte
                           (cl:format nil "~A (default ~A): "
                                      (%elisp-string->cl-string prompt)
                                      (%elisp-string->cl-string d)))
                          prompt))
             (input (read-from-minibuffer prompt*)))
        (when (and (stringp input)
                   (cl:string= (%elisp-string->cl-string input) "")
                   d)
          (setf input d))
        (cond
         ((not require-match) input)
         ((exact-member-p input cands) input)
         ((let ((uniq (unique-completion input cands)))
            (when uniq uniq)))
         (t
          (error "ELISP:COMPLETING-READ no match: %S" input)))))))

(cl:defun read-key-sequence (&optional _prompt &rest _args)
  "Bring-up subset of ELisp `read-key-sequence'.

Returns a vector of events."
  (declare (cl:ignore _prompt _args))
  (let ((events nil))
    (loop
      (let ((ev (read-event)))
        (push ev events)
        (let* ((seq (coerce (nreverse events) 'vector))
               (binding (key-binding seq t)))
          (when (or (null binding) (not (keymapp binding)))
            (setf *clemacs-this-command-keys* seq)
            (return seq)))))))

(cl:defun negative-argument (&optional _arg)
  "Bring-up subset of ELisp `negative-argument'.

This sets `prefix-arg' to the raw prefix marker `-' when no numeric prefix has
been started, or negates an existing numeric prefix."
  (declare (cl:ignore _arg))
  (cond
   ((null prefix-arg) (setf prefix-arg '-))
   ((eq prefix-arg '-) nil)
   ((integerp prefix-arg) (setf prefix-arg (- prefix-arg)))
   ((consp prefix-arg) (setf prefix-arg (list (- (prefix-numeric-value prefix-arg)))))
   (t (setf prefix-arg '-)))
  nil)

(cl:defun digit-argument (&optional _arg)
  "Bring-up subset of ELisp `digit-argument'.

This reads the digit from `last-command-event' and extends `prefix-arg'."
  (declare (cl:ignore _arg))
  (unless (integerp last-command-event)
    (return-from digit-argument nil))
  (let ((d (- last-command-event 48)))
    (unless (and (<= 0 d) (<= d 9))
      (return-from digit-argument nil))
    (cond
     ((null prefix-arg)
      (setf prefix-arg d))
     ((eq prefix-arg '-)
      (setf prefix-arg (- d)))
     ((integerp prefix-arg)
      (setf prefix-arg (if (minusp prefix-arg)
                           (- (+ (* (- prefix-arg) 10) d))
                           (+ (* prefix-arg 10) d))))
     ((consp prefix-arg)
      (setf prefix-arg (prefix-numeric-value prefix-arg))
      (digit-argument))
     (t
      (setf prefix-arg d))))
  nil)

(cl:defun universal-argument (&optional _arg)
  "Bring-up subset of ELisp `universal-argument' (C-u).

This builds `prefix-arg' for the *next* command by reading subsequent events:
- Repeated C-u multiplies by 4.
- Digits build a decimal numeric prefix.
- A leading `-' introduces a negative prefix.
The first non-argument event is pushed back onto `unread-command-events'."
  (declare (cl:ignore _arg))
  (let ((base (* 4 (prefix-numeric-value (or current-prefix-arg 1))))
        (sign 1)
        (num nil))
    (setf prefix-arg (list base))
    (loop
      (let ((ev (read-event)))
        (cond
         ;; C-u (control-u) is 21 in our TTY event encoding.
         ((and (integerp ev) (= ev 21) (null num) (= sign 1))
          (setf base (* base 4))
          (setf prefix-arg (list base)))
         ;; Leading '-' starts a negative numeric prefix.
         ((and (integerp ev) (= ev 45) (null num))
          (setf sign -1)
          (setf prefix-arg '-))
         ;; Digits build a decimal prefix (override the initial 4^n).
         ((and (integerp ev) (<= 48 ev) (<= ev 57))
          (let ((d (- ev 48)))
            (setf num (if num (+ (* num 10) d) d))
            (setf prefix-arg (* sign num))))
         (t
          (%clemacs--unread-push ev)
          (return))))))
  nil)

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

  (let* ((level (or (ignore-errors (uiop:getenv "CLEMACS_TTY_STARTUP_LEVEL")) "tty-editor"))
         (force-bringup-p (or (cl:string= level "none")
                              (cl:string= level "subr")))
         (shipped-global
           (let ((g (current-global-map)))
             (and g (keymapp g) g)))
         (shipped-ctl-x
           (cond
            ((and (boundp 'ctl-x-map) (keymapp (symbol-value 'ctl-x-map)))
             (symbol-value 'ctl-x-map))
            ((and (boundp 'ctl-x-map) (keymapp 'ctl-x-map))
             'ctl-x-map)
            (t nil)))
         (bringup-p (or force-bringup-p (null shipped-global) (null shipped-ctl-x)))
         (global (and (not bringup-p) shipped-global))
         (ctl-x (and (not bringup-p) shipped-ctl-x)))
    ;; For bring-up/debugging (`CLEMACS_TTY_STARTUP_LEVEL=subr|none`), prefer a
    ;; minimal local keymap so we don't override shipped bindings in `global-map`
    ;; / `ctl-x-map`.
    (when bringup-p
      (when (or (null *clemacs-tty-global-map*) (not (keymapp *clemacs-tty-global-map*)))
        (setf *clemacs-tty-global-map* (make-sparse-keymap)))
      (setf global *clemacs-tty-global-map*)
      (use-global-map global)

      (when (or (null *clemacs-tty-ctl-x-map*) (not (keymapp *clemacs-tty-ctl-x-map*)))
        (setf *clemacs-tty-ctl-x-map* (make-sparse-keymap)))
      (setf ctl-x *clemacs-tty-ctl-x-map*)
      (define-key global (vector 24) ctl-x)

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
      (define-key global (vector 21) 'universal-argument)         ; C-u

      ;; Editing.
      (define-key global (vector 127) 'clemacs-tty-delete-backward-char) ; DEL
      (define-key global (vector 13) 'clemacs-tty-newline)               ; RET

      ;; Default.
      (define-key global t 'clemacs-tty-self-insert-command))

    t))
