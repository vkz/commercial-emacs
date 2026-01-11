(in-package #:elisp)

(defstruct elisp-keymap
  (table (cl:make-hash-table :test 'cl:equal))
  (parent nil))

(cl:defun %keymap-backend (keymap)
  (cond
   ((typep keymap 'elisp-keymap) keymap)
   ((and (symbolp keymap) (cl:boundp keymap))
    (%keymap-backend (symbol-value keymap)))
   ((and (symbolp keymap) (fboundp keymap))
    (%keymap-backend (symbol-function keymap)))
   ((and (consp keymap) (eq (car keymap) 'keymap)
         (consp (cddr keymap))
         (typep (caddr keymap) 'elisp-keymap))
    (caddr keymap))
   (t
    (error "ELISP: expected keymap, got: ~S" keymap))))

(cl:defun keymapp (object)
  "Bring-up subset of ELisp `keymapp'."
  (let* ((km (cond
              ((not (symbolp object)) object)
              ((cl:boundp object) (symbol-value object))
              ((fboundp object) (symbol-function object))
              (t object))))
    (or (and (typep km 'elisp-keymap) t)
        (and (consp km) (eq (car km) 'keymap) t))))

(cl:defun keymap-parent (keymap)
  "Bring-up subset of ELisp `keymap-parent'."
  (elisp-keymap-parent (%keymap-backend keymap)))

(cl:defun set-keymap-parent (keymap parent)
  "Extremely small stub for ELisp `set-keymap-parent'."
  (let ((km (%keymap-backend keymap))
        (parent* (if (and (symbolp parent) (cl:boundp parent))
                     (symbol-value parent)
                     parent)))
    (when (and parent* (not (keymapp parent*)))
      (error "ELISP:SET-KEYMAP-PARENT expected a keymap parent, got: ~S" parent))
    (setf (elisp-keymap-parent km) parent*)
    keymap))

(cl:defun copy-keymap (keymap)
  "Bring-up subset of ELisp `copy-keymap'."
  (let* ((km (%keymap-backend keymap))
         (out (make-elisp-keymap)))
    (setf (elisp-keymap-parent out) (elisp-keymap-parent km))
    (maphash
     (lambda (k v)
       (setf (gethash k (elisp-keymap-table out)) v))
     (elisp-keymap-table km))
    (if (and (consp keymap) (eq (car keymap) 'keymap))
        (list 'keymap (cadr keymap) out)
        out)))

(cl:defun make-composed-keymap (maps &optional parent)
  "Bring-up subset of ELisp `make-composed-keymap'."
  (let* ((maps* (cond
                 ((null maps) nil)
                 ((and (symbolp maps) (cl:boundp maps)) (list (symbol-value maps)))
                 ((typep maps 'elisp-keymap) (list maps))
                 ((listp maps)
                  (mapcar (lambda (m)
                            (cond
                             ((and (symbolp m) (cl:boundp m)) (symbol-value m))
                             (t m)))
                          maps))
                 (t (error "ELISP:MAKE-COMPOSED-KEYMAP bad MAPS: ~S" maps))))
         (parent* (cond
                   ((null parent) nil)
                   ((and (symbolp parent) (cl:boundp parent)) (symbol-value parent))
                   (t parent)))
         (out (make-elisp-keymap)))
    ;; Earlier keymaps should win.
    (dolist (m (reverse maps*))
      (when (typep m 'elisp-keymap)
        (maphash
         (lambda (k v)
           (setf (gethash k (elisp-keymap-table out)) v))
         (elisp-keymap-table m))))
    (when parent*
      (set-keymap-parent out parent*))
    (list 'keymap nil out)))

(defparameter system-type 'darwin)
(cl:defvar password-word-equivalents
  '("password" "passcode" "passphrase" "pass phrase" "pin"
    "decryption key" "encryption key"
    "암호"
    "パスワード"
    "ପ୍ରବେଶ ସଙ୍କେତ"
    "ពាក្យសម្ងាត់"
    "adgangskode"
    "contraseña"
    "contrasenya"
    "geslo"
    "hasło"
    "heslo"
    "iphasiwedi"
    "jelszó"
    "lösenord"
    "lozinka"
    "mật khẩu"
    "mot de passe"
    "parola"
    "pasahitza"
    "passord"
    "passwort"
    "pasvorto"
    "salasana"
    "senha"
    "slaptažodis"
    "wachtwoord"
    "كلمة السر"
    "ססמה"
    "лозинка"
    "пароль"
    "गुप्तशब्द"
    "शब्दकूट"
    "પાસવર્ડ"
    "సంకేతపదము"
    "ਪਾਸਵਰਡ"
    "ಗುಪ್ತಪದ"
    "கடவுச்சொல்"
    "അടയാളവാക്ക്"
    "গুপ্তশব্দ"
    "পাসওয়ার্ড"
    "රහස්පදය"
    "密码"
    "密碼")
  "Bring-up default for `password-word-equivalents' (normally from mule-conf.el).")

(cl:defvar password-colon-equivalents
  (list #x003a #xFF1A #xFE55 #xFE13 #x17D6)
  "Bring-up default for `password-colon-equivalents' (normally from mule-conf.el).")

(cl:defvar menu-bar-final-items nil
  "Bring-up stub for the C variable `menu-bar-final-items'.")

(cl:defun system-name ()
  "Bring-up subset of ELisp `system-name'."
  (or (ignore-errors (uiop:hostname))
      (ignore-errors (machine-instance))
      "unknown"))

(cl:defun current-time ()
  "Bring-up subset of ELisp `current-time'.

  Returns an Emacs-style time value: (HI LO USEC PSEC), where seconds are encoded
  as HI*65536 + LO."
  (multiple-value-bind (sec usec) (sb-ext:get-time-of-day)
    (let ((hi (floor sec 65536))
          (lo (mod sec 65536)))
      (list hi lo usec 0))))

(cl:defun format-time-string (format &optional time _universal _zone)
  "Bring-up subset of ELisp `format-time-string'.

Supports the conversion specs needed by ERT: %Y %m %d %T %z."
  (declare (cl:ignore _universal _zone))
  (unless (stringp format)
    (error "ELISP:FORMAT-TIME-STRING expects string format, got: ~S" format))
  (labels ((time-seconds (tval)
             (cond
              ((null tval)
               (time-seconds (current-time)))
              ((and (consp tval)
                    (integerp (first tval))
                    (integerp (second tval)))
               (+ (* (first tval) 65536) (second tval)))
              ((integerp tval) tval)
              (t
               (error "ELISP:FORMAT-TIME-STRING unsupported time: ~S" tval))))
           (pad2 (n)
             (cl:format nil "~2,'0D" n))
           (pad2space (n)
             (cl:format nil "~2,' D" n))
           (pad4 (n)
             (cl:format nil "~4,'0D" n))
           (mon-abbrev (n)
             (svref #("Jan" "Feb" "Mar" "Apr" "May" "Jun"
                      "Jul" "Aug" "Sep" "Oct" "Nov" "Dec")
                    (1- n)))
           (tz-offset (zone-west)
             ;; CL zone is hours west of UTC; ISO8601 expects offset east.
             (let* ((east (- zone-west))
                    (sign (if (minusp east) #\- #\+))
                    (abs (abs east))
                    (hh (floor abs))
                    (mm 0))
               (cl:format nil "~C~2,'0D~2,'0D" sign hh mm))))
    (let* ((sec (time-seconds time))
           ;; CL universal time is seconds since 1900-01-01 UTC.
           (ut (+ sec 2208988800))
           (ss 0) (mm 0) (hh 0) (dd 0) (mo 0) (yy 0) (dow 0) (dst 0) (zone 0))
      (declare (cl:ignore dow dst))
      (multiple-value-setq (ss mm hh dd mo yy dow dst zone)
        (decode-universal-time ut))
      (let* ((fmt (%elisp-string->cl-string format))
             (len (length fmt)))
        (cl:with-output-to-string (out)
          (loop for i from 0 below len do
            (let ((ch (char fmt i)))
              (if (char= ch #\%)
                  (let ((next (and (< (1+ i) len) (char fmt (1+ i)))))
                    (unless next
                      (write-char ch out)
                      (return))
                    (incf i)
                    (case next
                      (#\Y (write-string (pad4 yy) out))
                      (#\y (write-string (pad2 (mod yy 100)) out))
                      (#\b (write-string (mon-abbrev mo) out))
                      (#\m (write-string (pad2 mo) out))
                      (#\d (write-string (pad2 dd) out))
                      (#\e (write-string (pad2space dd) out))
                      (#\H (write-string (pad2 hh) out))
                      (#\M (write-string (pad2 mm) out))
                      (#\S (write-string (pad2 ss) out))
                      (#\T (write-string (cl:format nil "~2,'0D:~2,'0D:~2,'0D" hh mm ss) out))
                      (#\z (write-string (tz-offset zone) out))
                      (t
                       ;; Unknown spec: emit literally.
                       (write-char #\% out)
                       (write-char next out))))
                  (write-char ch out)))))))))

(cl:defun program-version ()
  "Bring-up subset of ELisp `program-version'."
  emacs-version)

(defparameter system-configuration
  (cl:format nil "~A-apple-darwin"
             (string-downcase (machine-type))))

(defvar *global-map* nil)
(cl:defvar special-mode-map (make-elisp-keymap))
(defparameter minibuffer-local-map (make-elisp-keymap))
(cl:defvar local-map nil)
(cl:defvar local-function-key-map (make-elisp-keymap))
(cl:defvar search-map (list 'keymap nil (make-elisp-keymap)))
(defparameter find-function-space-re "")
(cl:defvar find-function-regexp-alist nil)
(defparameter buffer-file-name nil)
(cl:defvar fill-column 70)
(defparameter noninteractive t)
(defparameter current-load-list nil)
(cl:defvar load-history nil)
(cl:defvar after-load-alist nil)
(cl:defvar describe-symbol-backends nil)
(cl:defvar minor-mode-alist nil)
(cl:defvar help-char 8)
(cl:defvar meta-prefix-char 27)
(cl:defvar minibuffer-prompt-properties nil)
(cl:defvar minibuffer-setup-hook nil)
(cl:defvar font-lock-mode nil)
(cl:defvar font-lock-function nil)

;; ---------------------------------------------------------------------------
;; Help buffers (minimal stubs for upstream ERT help output)
;; ---------------------------------------------------------------------------

(cl:defun called-interactively-p (&optional _kind)
  "Bring-up stub for ELisp `called-interactively-p'."
  (declare (cl:ignore _kind))
  nil)

(cl:defun help-buffer ()
  "Bring-up subset of ELisp `help-buffer'."
  (get-buffer-create "*Help*")
  "*Help*")

(cl:defmacro make-help-screen (name &rest _args)
  "Bring-up stub for ELisp `make-help-screen'.

This macro normally defines interactive help helpers.  For clemacs bring-up,
define NAME as a no-op function and ignore the rest of the form so its
arguments are not evaluated."
  (declare (cl:ignore _args))
  `(cl:defun ,name (&rest _ignored)
     (declare (cl:ignore _ignored))
     nil))

(cl:defmacro with-help-window (buffer-name &body body)
  "Bring-up subset of ELisp `with-help-window'."
  (let ((buf (cl:gensym "HELP-BUF-")))
    `(let ((,buf ,buffer-name))
      (display-buffer ,buf)
       (with-current-buffer ,buf
         (let ((inhibit-read-only t))
           (erase-buffer))
         ,@body))))

(cl:defun help-setup-xref (&rest _args)
  "Bring-up stub for ELisp `help-setup-xref'."
  (declare (cl:ignore _args))
  nil)

(cl:defun help-xref-button (&rest _args)
  "Bring-up stub for ELisp `help-xref-button'."
  (declare (cl:ignore _args))
  nil)

(cl:defun help-add-fundoc-usage (doc &rest _args)
  "Bring-up stub for ELisp `help-add-fundoc-usage'."
  (declare (cl:ignore _args))
  doc)

(cl:defun help-function-arglist (&rest _args)
  "Bring-up stub for ELisp `help-function-arglist'."
  (declare (cl:ignore _args))
  nil)

(cl:defun documentation (object &optional _raw)
  "Bring-up subset of ELisp `documentation'."
  (declare (cl:ignore _raw))
  ;; Use CL's doc-type symbol, not ELISP::FUNCTION.
  (ignore-errors (cl:documentation object 'cl:function)))

(cl:defun find-lisp-object-file-name (&rest _args)
  "Bring-up stub for ELisp `find-lisp-object-file-name'."
  (declare (cl:ignore _args))
  nil)

(cl:defun help-fns--signature (&rest _args)
  "Bring-up stub for ELisp `help-fns--signature'."
  (declare (cl:ignore _args))
  nil)

(cl:defun help-fns-short-filename (filename)
  "Bring-up stub for ELisp `help-fns-short-filename'."
  filename)

(cl:defun help-insert-xref-button (&rest _args)
  "Bring-up stub for ELisp `help-insert-xref-button'."
  (declare (cl:ignore _args))
  nil)

(cl:defun help-split-fundoc (doc &rest _args)
  "Bring-up stub for ELisp `help-split-fundoc'."
  (declare (cl:ignore _args))
  doc)

(cl:defun apropos-internal (&rest _args)
  "Bring-up stub for ELisp `apropos-internal'."
  (declare (cl:ignore _args))
  nil)

(cl:defun ert-test-at-point (&rest _args)
  "Bring-up stub for ERT helper `ert-test-at-point'."
  (declare (cl:ignore _args))
  nil)

(cl:defun substitute-command-keys (string)
  "Bring-up stub for ELisp `substitute-command-keys'."
  string)

(cl:defun event-modifiers (_event)
  "Bring-up subset of ELisp `event-modifiers' (TTY bring-up).

clemacs currently represents TTY key events as:
- integer character codes, or
- symbols such as LEFT/RIGHT/UP/DOWN.

Return nil (no modifiers) for now."
  (declare (cl:ignore _event))
  nil)

(cl:defun keymap-prompt (keymap)
  "Bring-up subset of ELisp `keymap-prompt'."
  (let ((km (cond
             ((not (symbolp keymap)) keymap)
             ((cl:boundp keymap) (symbol-value keymap))
             ((fboundp keymap) (symbol-function keymap))
             (t keymap))))
    (cond
     ((and (consp km) (eq (car km) 'keymap) (stringp (cadr km))) (cadr km))
     (t nil))))

(cl:defvar key-substitution-in-progress nil)

(cl:defun substitute-key-definition-key (defn olddef newdef prefix keymap)
  "Bring-up subset of `substitute-key-definition-key'.

This is defined in upstream `lisp/subr.el', but is referenced earlier in that
file before its definition, leading to host CL \"undefined function\" warnings
while compiling under SBCL.  Provide a compatible implementation here."
  (let (inner-def skipped menu-item)
    ;; Find the actual command name within the binding.
    (if (eq (car-safe defn) 'menu-item)
        (setf menu-item defn
              defn (nth 2 defn))
        (progn
          ;; Skip past menu-prompt.
          (loop while (stringp (car-safe defn)) do
            (push (car defn) skipped)
            (setf defn (cdr defn)))
          ;; Skip past cached key-equivalence data for menu items.
          (when (consp (car-safe defn))
            (setf defn (cdr defn)))))
    (if (or (eq defn olddef)
            (and (or (stringp defn) (vectorp defn))
                 (equal defn olddef)))
        (define-key keymap prefix
          (if menu-item
              (let ((copy (copy-sequence menu-item)))
                (setcar (nthcdr 2 copy) newdef)
                copy)
              (nconc (nreverse skipped) newdef)))
        (progn
          (setf inner-def (or (indirect-function defn) defn))
          (when (and (keymapp inner-def)
                     (let ((elt (lookup-key keymap prefix)))
                       (or (null elt) (natnump elt) (keymapp elt)))
                     (not (memq inner-def key-substitution-in-progress)))
            (substitute-key-definition olddef newdef keymap inner-def prefix))))))

(cl:defun help-form-show ()
  "Bring-up subset of ELisp `help-form-show'."
  (let ((hf (and (boundp 'help-form) (symbol-value 'help-form))))
    (when hf
      (let ((s (cond
                ((stringp hf) hf)
                (t (prin1-to-string (eval hf))))))
        (message "%s" s)
        t))))

(cl:defun progress-reporter-do-update (reporter value &optional suffix)
  "Bring-up subset of `progress-reporter-do-update'.

This exists primarily to reduce forward-reference warnings while compiling
upstream `lisp/subr.el'.  For clemacs bring-up we avoid echo-area churn and
just update the in-memory reporter object when possible."
  (declare (cl:ignore value))
  (when (consp reporter)
    (let ((params (cdr reporter)))
      (when (and suffix (vectorp params) (> (length params) 6))
        (setf (aref params 6) suffix))))
  reporter)

(cl:defun derived-mode--flush (mode)
  "Bring-up subset of `derived-mode--flush'."
  (put mode 'derived-mode--all-parents nil)
  (let ((followers (get mode 'derived-mode--followers)))
    (when followers
      (put mode 'derived-mode--followers nil)
      (mapc #'derived-mode--flush followers))))

(cl:defun fill-region-as-paragraph (&rest _args)
  "Bring-up stub for ELisp `fill-region-as-paragraph'."
  (declare (cl:ignore _args))
  nil)

(cl:defun font-lock-default-function (&optional _enabledp)
  "Bring-up stub for ELisp `font-lock-default-function'."
  (declare (cl:ignore _enabledp))
  nil)

(cl:defun font-lock-mode (&optional arg)
  "Bring-up subset of ELisp `font-lock-mode'.

For bring-up we implement only:
- enabling/disabling the buffer-local `font-lock-mode' variable, and
- calling `font-lock-function' when present (ERT uses this to redraw results)."
  (let* ((cur (and (boundp 'font-lock-mode) (symbol-value 'font-lock-mode)))
         (enable
           (cond
            ((null arg) (not cur))
            ((eq arg t) t)
            ((and (integerp arg) (> arg 0)) t)
            (t nil))))
    (make-local-variable 'font-lock-mode)
    (set 'font-lock-mode (and enable t))
    (when (boundp 'font-lock-function)
      (let ((fn (ignore-errors (symbol-value 'font-lock-function))))
        (when (or (functionp fn) (and (symbolp fn) (fboundp fn)))
          (funcall fn enable))))
    (symbol-value 'font-lock-mode)))

(cl:defun file-name-base (filename)
  "Bring-up subset of ELisp `file-name-base'."
  (unless (stringp filename)
    (error "ELISP:FILE-NAME-BASE expects a string, got: ~S" filename))
  (let* ((s (if (unibyte-string-p filename)
                (%elisp-string->cl-string filename)
                filename))
         (slash (or (position #\/ s :from-end t)
                    (position #\\ s :from-end t)))
         (name (subseq s (if slash (1+ slash) 0)))
         (dot (position #\. name :from-end t)))
    (cond
     ((and dot (plusp dot))
      (subseq name 0 dot))
	     (t name))))

(cl:defun file-name-nondirectory (filename)
  "Bring-up subset of ELisp `file-name-nondirectory'."
  (unless (stringp filename)
    (error "ELISP:FILE-NAME-NONDIRECTORY expects a string, got: ~S" filename))
  (let* ((s (%file-name->cl-string filename))
         (slash (or (position #\/ s :from-end t)
                    (position #\\ s :from-end t))))
    (subseq s (if slash (1+ slash) 0))))
