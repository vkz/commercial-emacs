(in-package #:elisp)

(defstruct elisp-keymap
  (table (cl:make-hash-table :test 'cl:equal))
  (parent nil))

(cl:defun %keymap-backend (keymap)
  (cond
   ((typep keymap 'elisp-keymap) keymap)
   ((and (symbolp keymap) (cl:boundp keymap))
    (%keymap-backend (symbol-value keymap)))
   ((and (consp keymap) (eq (car keymap) 'keymap)
         (consp (cddr keymap))
         (typep (caddr keymap) 'elisp-keymap))
    (caddr keymap))
   (t
    (error "ELISP: expected keymap, got: ~S" keymap))))

(cl:defun keymapp (object)
  "Bring-up subset of ELisp `keymapp'."
  (let ((km (if (and (symbolp object) (cl:boundp object))
                (symbol-value object)
                object)))
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

(cl:defun substitute-command-keys (string)
  "Bring-up stub for ELisp `substitute-command-keys'."
  string)

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
