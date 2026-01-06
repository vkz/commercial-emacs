(in-package #:clemacs)

(defstruct tty-state
  (buf (make-buffer) :type buffer)
  (top-line 0 :type fixnum)
  (goal-col nil)
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

(defun %tty-read-keyseq (prefixes)
  (let ((k (%tty-read-key)))
    (if (member k prefixes :test #'equal)
        (list k (%tty-read-key))
        (list k))))

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
           (text (buffer-text buf))
           (path (buffer-path buf))
           (line-starts (%buffer-line-starts text))
           (frame (make-empty-grid-frame rows cols)))
      (setf (aref (grid-frame-lines frame) 0)
            (format nil "clemacs tty: ~A" (or path "<buffer>")))
      (setf (aref (grid-frame-lines frame) 1) "")

      (multiple-value-bind (cursor-line cursor-col) (buffer-line-column buf)
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
  (multiple-value-bind (frame top)
      (%tty-build-grid-frame (tty-state-buf state) (tty-state-top-line state))
    (%tty-apply-grid-patch (grid-frame->patch frame (tty-state-frame state)) frame)
    (setf (tty-state-frame state) frame)
    top))

(defun %tty-save (buf)
  (unless (buffer-save buf)
    (tty-write-string "\a")
    (return-from %tty-save nil))
  t)

(defun %cmd-quit (_state)
  (declare (ignore _state))
  :quit)

(defun %cmd-save (state)
  (let ((buf (tty-state-buf state)))
    (unless (buffer-path buf)
      (let ((path (%tty-prompt "Save as: ")))
        (when (and path (not (string= path "")))
          (setf (buffer-path buf) path))))
    (%tty-save buf)
    state))

(defun %cmd-left (state)
  (buffer-backward-char (tty-state-buf state))
  (setf (tty-state-goal-col state) nil)
  state)

(defun %cmd-right (state)
  (buffer-forward-char (tty-state-buf state))
  (setf (tty-state-goal-col state) nil)
  state)

(defun %cmd-up (state)
  (multiple-value-bind (_buf goal)
      (buffer-move-vertical (tty-state-buf state) -1 :goal-column (tty-state-goal-col state))
    (declare (ignore _buf))
    (setf (tty-state-goal-col state) goal))
  state)

(defun %cmd-down (state)
  (multiple-value-bind (_buf goal)
      (buffer-move-vertical (tty-state-buf state) 1 :goal-column (tty-state-goal-col state))
    (declare (ignore _buf))
    (setf (tty-state-goal-col state) goal))
  state)

(defun %cmd-backspace (state)
  (buffer-delete-backward (tty-state-buf state))
  (setf (tty-state-goal-col state) nil)
  state)

(defun %cmd-enter (state)
  (buffer-insert-char (tty-state-buf state) #\Newline)
  (setf (tty-state-goal-col state) nil)
  state)

(defun %cmd-insert (state ch)
  (buffer-insert-char (tty-state-buf state) ch)
  (setf (tty-state-goal-col state) nil)
  state)

(defun %make-command-table ()
  (let ((m (make-hash-table :test 'equal)))
    (setf (gethash (list (list :ctrl #\q)) m) #'%cmd-quit)
    (setf (gethash (list (list :ctrl #\s)) m) #'%cmd-save)
    (setf (gethash (list (list :ctrl #\b)) m) #'%cmd-left)
    (setf (gethash (list (list :ctrl #\f)) m) #'%cmd-right)
    (setf (gethash (list (list :ctrl #\p)) m) #'%cmd-up)
    (setf (gethash (list (list :ctrl #\n)) m) #'%cmd-down)

    (setf (gethash (list :left) m) #'%cmd-left)
    (setf (gethash (list :right) m) #'%cmd-right)
    (setf (gethash (list :up) m) #'%cmd-up)
    (setf (gethash (list :down) m) #'%cmd-down)

    (setf (gethash (list :backspace) m) #'%cmd-backspace)
    (setf (gethash (list :enter) m) #'%cmd-enter)

    (setf (gethash (list (list :ctrl #\x) (list :ctrl #\c)) m) #'%cmd-quit)
    (setf (gethash (list (list :ctrl #\x) (list :ctrl #\s)) m) #'%cmd-save)
    m))

(defun tty-main (&key path)
  (let* ((dump (uiop:getenv "CLEMACS_GRID_PATCH_DUMP"))
         (path* (and path (not (string= path "")) path))
         (state (make-tty-state :buf (if path* (buffer-load-file path*) (make-buffer)))))
    (when (and dump (not (string= dump "")))
      (setf *grid-patch-sinks*
            (list (make-grid-patch-jsonl-sink dump))))
    (unwind-protect
        (progn
          (tty-enter-raw)
          (let* ((prefixes (list (list :ctrl #\x)))
                 (cmds (%make-command-table)))
            (loop
              (setf (tty-state-top-line state)
                    (%tty-draw state))
              (let* ((keys (%tty-read-keyseq prefixes))
                     (cmd (gethash keys cmds)))
                (cond
                 (cmd
                  (let ((r (funcall cmd state)))
                    (when (eq r :quit)
                      (return 0))))
                 ((and (= (length keys) 1) (characterp (first keys)))
                  (%cmd-insert state (first keys)))
                 (t nil)))))))
      (ignore-errors (tty-exit-raw))
      (%tty-clear)))
