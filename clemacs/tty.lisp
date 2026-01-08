(in-package #:clemacs)

(defstruct tty-state
  (buf nil)
  (top-line 0 :type fixnum)
  (frame nil))

(defun %tty-read-key ()
  (let ((b (tty-read-byte)))
    (cond
     ((= b 27) ; ESC sequence
      (let ((b1 (tty-read-byte)))
        (cond
         ((= b1 91) ; [
          (let ((b2 (tty-read-byte)))
            (case b2
              (65 :up)
              (66 :down)
              (67 :right)
              (68 :left)
              (t :esc))))
         (t :esc))))
     ((or (= b 10) (= b 13)) :enter)
     ((or (= b 8) (= b 127)) :backspace)
     ((and (<= 1 b) (<= b 26))
      (list :ctrl (code-char (+ b 96))))
     ((and (<= 32 b) (<= b 126))
      (code-char b))
     (t (list :byte b)))))

(defparameter +tty-elisp-event-left+ (cl:intern "LEFT" (find-package "ELISP")))
(defparameter +tty-elisp-event-right+ (cl:intern "RIGHT" (find-package "ELISP")))
(defparameter +tty-elisp-event-up+ (cl:intern "UP" (find-package "ELISP")))
(defparameter +tty-elisp-event-down+ (cl:intern "DOWN" (find-package "ELISP")))

(defun %tty-read-event ()
  "Return a minimal Emacs-style event for the clemacs TTY loop.

Events are either integer character codes (including control codes), or ELISP
package symbols for special keys (LEFT/RIGHT/UP/DOWN)."
  (let ((k (%tty-read-key)))
    (cond
     ((and (consp k) (eq (first k) :ctrl) (characterp (second k)))
      ;; k is (:ctrl #\x) from bytes 1..26.
      (- (char-code (second k)) 96))
     ((characterp k) (char-code k))
     ((eq k :enter) 13)
     ((eq k :backspace) 127)
     ((eq k :left)
      (ignore-errors (elisp::internal-event-symbol-parse-modifiers +tty-elisp-event-left+))
      +tty-elisp-event-left+)
     ((eq k :right)
      (ignore-errors (elisp::internal-event-symbol-parse-modifiers +tty-elisp-event-right+))
      +tty-elisp-event-right+)
     ((eq k :up)
      (ignore-errors (elisp::internal-event-symbol-parse-modifiers +tty-elisp-event-up+))
      +tty-elisp-event-up+)
     ((eq k :down)
      (ignore-errors (elisp::internal-event-symbol-parse-modifiers +tty-elisp-event-down+))
      +tty-elisp-event-down+)
     ((eq k :esc) 27)
     ((and (consp k) (eq (first k) :byte) (integerp (second k)))
      (second k))
     (t 0))))

(defun %tty-prompt (prompt)
  (multiple-value-bind (rows cols) (%tty-terminal-size)
    (let ((input ""))
      (loop
        (%tty-move-cursor rows 1)
        (%tty-clear-eol)
        (tty-write-string prompt)
        (let* ((avail (max 0 (- cols (length prompt))))
               (vis (if (> (length input) avail) (subseq input (- (length input) avail)) input)))
          (tty-write-string vis))
        (%tty-clear-eol)
        (let ((k (%tty-read-key)))
          (cond
           ((equal k (list :ctrl #\g))
            (return nil))
           ((eq k :enter)
            (return input))
           ((eq k :backspace)
            (when (> (length input) 0)
              (setf input (subseq input 0 (1- (length input))))))
           ((characterp k)
            (setf input (concatenate 'string input (string k))))
           (t nil)))))))

(defun %tty-clear ()
  (tty-write-string (format nil "~C[2J~C[H" #\Esc #\Esc)))

(defun %tty-move-cursor (row col)
  (tty-write-string (format nil "~C[~D;~DH" #\Esc row col)))

(defun %tty-clear-eol ()
  (tty-write-string (format nil "~C[K" #\Esc)))

(defun %tty-terminal-size ()
  (handler-case
      (multiple-value-call #'values (tty-winsize))
    (error () (values 24 80))))

(defun %buffer-line-starts (text)
  (let ((starts (list 0)))
    (loop for i from 0 below (length text) do
      (when (char= (aref text i) #\Newline)
        (push (1+ i) starts)))
    (coerce (nreverse starts) 'vector)))

(defun %line-range (line-starts text line)
  (let* ((start (aref line-starts line))
         (next-start (if (< (1+ line) (length line-starts))
                         (aref line-starts (1+ line))
                         (length text)))
         (end (if (and (< next-start (length text)) (char= (aref text (1- next-start)) #\Newline))
                  (1- next-start)
                  next-start)))
    (values start end)))

(defun %tty-build-grid-frame (buf top-line)
  (multiple-value-bind (rows cols) (%tty-terminal-size)
    (let* ((header-lines 2)
           (footer-lines 2)
           (content-lines (max 1 (- rows header-lines footer-lines)))
           (text (elisp::elisp-buffer-text buf))
           (path elisp::clemacs-tty-path)
           (line-starts (%buffer-line-starts text))
           (frame (make-empty-grid-frame rows cols)))
      (setf (aref (grid-frame-lines frame) 0)
            (format nil "clemacs tty: ~A"
                    (or (and path (not (string= path "")) path)
                        (let ((bn (elisp::buffer-name buf)))
                          (if bn (elisp::%elisp-string->cl-string bn) "<buffer>"))
                        "<buffer>")))
      (setf (aref (grid-frame-lines frame) 1) "")

      (let* ((idx (max 0 (min (1- (elisp::elisp-buffer-point buf)) (length text))))
             (cursor-line (%line-number-at line-starts idx))
             (cursor-col (elisp::current-column)))
        (let* ((max-top (max 0 (- (length line-starts) content-lines)))
               (top (min (max 0 top-line) max-top))
               (top (cond
                     ((< cursor-line top) cursor-line)
                     ((>= cursor-line (+ top content-lines)) (- cursor-line content-lines -1))
                     (t top))))
          (setf top (min (max 0 top) max-top))

          (dotimes (i content-lines)
            (let ((line (+ top i))
                  (row (+ header-lines i)))
              (setf (aref (grid-frame-lines frame) row)
                    (if (>= line (length line-starts))
                        ""
                        (multiple-value-bind (start end) (%line-range line-starts text line)
                          (subseq text start end))))))

          (setf (grid-frame-scroll-from-row frame) (+ header-lines 1)
                (grid-frame-scroll-to-row frame) (+ header-lines content-lines))

          (let ((blank-row (+ header-lines content-lines)))
            (when (< blank-row rows)
              (setf (aref (grid-frame-lines frame) blank-row) "")))
          (let ((help-row (+ header-lines content-lines 1)))
            (when (< help-row rows)
              (setf (aref (grid-frame-lines frame) help-row)
                    "C-x C-c quit  C-x C-s save  arrows/C-b/C-f/C-p/C-n move")))

          (setf (grid-frame-cursor-row frame) (+ header-lines 1 (- cursor-line top))
                (grid-frame-cursor-col frame) (min cols (1+ cursor-col)))
          (values frame top))))))

(defun %tty-render-grid-frame (frame)
  (%tty-clear)
  (let ((rows (grid-frame-rows frame))
        (cols (grid-frame-cols frame)))
    (dotimes (i rows)
      (let* ((line (aref (grid-frame-lines frame) i))
             (vis (if (> (length line) cols) (subseq line 0 cols) line)))
        (tty-write-string vis)
        (%tty-clear-eol)
        (when (< i (1- rows))
          (tty-write-string "~%"))))
    (%tty-move-cursor (max 1 (min rows (grid-frame-cursor-row frame)))
                      (max 1 (min cols (grid-frame-cursor-col frame))))))

(defun %tty-apply-grid-patch (ops frame)
  (let ((rows (grid-frame-rows frame))
        (cols (grid-frame-cols frame)))
    (dolist (op ops)
      (case (getf op :op)
        (:clear
         (%tty-clear))
        (:put-row
         (let* ((row (getf op :row))
                (text (getf op :text)))
           (%tty-move-cursor (max 1 (min rows row)) 1)
           (let ((vis (if (and (stringp text) (> (length text) cols))
                          (subseq text 0 cols)
                          (or text ""))))
             (tty-write-string vis))
           (%tty-clear-eol)))
        (:clear-eol
         (let ((row (getf op :row))
               (col (getf op :col)))
           (%tty-move-cursor (max 1 (min rows row))
                             (max 1 (min cols (or col 1))))
           (%tty-clear-eol)))
        (:scroll
         (let ((from (getf op :from))
               (to (getf op :to))
               (n (getf op :n)))
           (when (and (integerp from) (integerp to) (integerp n) (not (zerop n)))
             ;; Set scroll region, scroll, then restore full region.
             (tty-write-string (format nil "~C[~D;~Dr" #\Esc from to))
             (%tty-move-cursor from 1)
             (cond
              ((plusp n)
               ;; Positive = down (insert blank lines at top of region).
               (tty-write-string (format nil "~C[~DT" #\Esc n)))
              ((minusp n)
               ;; Negative = up (insert blank lines at bottom of region).
               (tty-write-string (format nil "~C[~DS" #\Esc (- n)))))
             (tty-write-string (format nil "~C[r" #\Esc)))))
        (:set-cursor
         (let ((row (getf op :row))
               (col (getf op :col)))
           (%tty-move-cursor (max 1 (min rows row))
                             (max 1 (min cols col)))))
        (otherwise
         (error "Unknown grid patch op: ~S" (getf op :op)))))))

(defun %tty-draw (state)
  (let ((buf (tty-state-buf state)))
    (when buf
      (elisp::set-buffer buf))
    (multiple-value-bind (frame top)
        (%tty-build-grid-frame buf (tty-state-top-line state))
      (%tty-apply-grid-patch (grid-frame->patch frame (tty-state-frame state)) frame)
      (setf (tty-state-frame state) frame)
      top)))

(defun %tty-project-root ()
  (let* ((clemacs-dir (uiop:ensure-directory-pathname (asdf:system-source-directory :clemacs)))
         (root (uiop:pathname-parent-directory-pathname clemacs-dir)))
    (uiop:ensure-directory-pathname root)))

(defun %tty-maybe-load-startup ()
  ;; Only load startup if it looks like we are still in the minimal
  ;; bring-up environment (i.e. `lisp/subr.el` has not established
  ;; `global-map` yet).  `emacs-main` already loads a startup manifest.
  (when (or (not (elisp::boundp 'elisp::global-map))
            (not (ignore-errors (elisp::keymapp (elisp::symbol-value 'elisp::global-map)))))
    (let ((project-root (%tty-project-root)))
      (let* ((level (or (uiop:getenv "CLEMACS_TTY_STARTUP_LEVEL") "subr")))
        (format t "[clemacs] loading startup (~A)~%" level)
        (finish-output)
        (handler-case
          (cond
           ((string= level "none")
            nil)
           ((string= level "subr")
            ;; Minimal set to obtain shipped keymaps (`global-map`, `ctl-x-map`)
            ;; without paying the full startup.manifest cost in the TTY loop.
            (elisp:load-elisp-file
             (merge-pathnames #p"lisp/emacs-lisp/backquote.el" project-root))
            (elisp:load-elisp-file
             (merge-pathnames #p"lisp/subr.el" project-root)))
           (t
            (let ((manifest (pathname (format nil "clemacs/contract/startup.~A.files" level))))
              (elisp:load-elisp-manifest
               :project-root project-root
               :manifest manifest
               :skip-file #p"clemacs/contract/lisp.allowed-skip.files"))))
          (error (e)
            (format *error-output* "[clemacs] startup load failed (continuing): ~A~%" e)
            (finish-output *error-output*)))))))

(defun tty-main (&key path)
  (let* ((dump (uiop:getenv "CLEMACS_GRID_PATCH_DUMP"))
         (path* (and path (not (string= path "")) path))
         (state (make-tty-state)))
    (when (and dump (not (string= dump "")))
      (setf *grid-patch-sinks*
            (list (make-grid-patch-jsonl-sink dump))))
    (unwind-protect
        (progn
          (%tty-maybe-load-startup)
          (tty-enter-raw)
          (let ((buf (elisp::get-buffer-create (or path* "*scratch*"))))
            (elisp::set-buffer buf)
            (setf elisp::noninteractive nil)
            (setf elisp::clemacs-tty-path path*)
            (when path*
              (elisp::insert-file-contents path* nil nil nil t))
            (elisp::goto-char (elisp::point-max))
            (elisp::clemacs-tty-setup :path path*)
            (setf (tty-state-buf state) buf)
            (loop
              (setf (tty-state-top-line state)
                    (%tty-draw state))
              (handler-case
                  (let* ((keys (elisp::read-key-sequence nil))
                         (cmd (elisp::key-binding keys t)))
                    (if (and cmd (not (integerp cmd)) (not (elisp::keymapp cmd)))
                        (elisp::command-execute cmd)
                        (tty-write-string "\a")))
                (clemacs-quit ()
                  (return 0))
                (error ()
                  (tty-write-string "\a"))))))
      (ignore-errors (tty-exit-raw))
      (%tty-clear))))
