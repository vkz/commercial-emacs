(in-package #:clemacs)

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

(defun %buffer-line-starts (buffer)
  (let ((starts (list 0)))
    (loop for i from 0 below (length buffer) do
      (when (char= (aref buffer i) #\Newline)
        (push (1+ i) starts)))
    (coerce (nreverse starts) 'vector)))

(defun %line-number-at (line-starts cursor)
  (let ((n (length line-starts))
        (best 0))
    (dotimes (i n best)
      (let ((start (aref line-starts i)))
        (when (> start cursor)
          (return best))
        (setf best i)))))

(defun %line-start (line-starts line)
  (aref line-starts line))

(defun %line-end (line-starts buffer line)
  (let ((n (length line-starts)))
    (if (< (1+ line) n)
        (aref line-starts (1+ line))
        (length buffer))))

(defun %line-range (line-starts buffer line)
  (let* ((start (%line-start line-starts line))
         (next-start (%line-end line-starts buffer line))
         (end (if (and (< next-start (length buffer)) (char= (aref buffer (1- next-start)) #\Newline))
                  (1- next-start)
                  next-start)))
    (values start end)))

(defun %cursor-line-col (line-starts cursor)
  (let* ((line (%line-number-at line-starts cursor))
         (start (%line-start line-starts line))
         (col (- cursor start)))
    (values line col)))

(defun %tty-move-up (buffer line-starts cursor goal-col)
  (multiple-value-bind (line col) (%cursor-line-col line-starts cursor)
    (declare (ignore col))
    (when (= line 0)
      (return-from %tty-move-up (values cursor goal-col)))
    (let* ((want (or goal-col (nth-value 1 (%cursor-line-col line-starts cursor))))
           (prev-line (1- line)))
      (multiple-value-bind (start end) (%line-range line-starts buffer prev-line)
        (let* ((len (- end start))
               (new-cursor (+ start (min want len))))
          (values new-cursor want))))))

(defun %tty-move-down (buffer line-starts cursor goal-col)
  (multiple-value-bind (line col) (%cursor-line-col line-starts cursor)
    (declare (ignore col))
    (when (>= (1+ line) (length line-starts))
      (return-from %tty-move-down (values cursor goal-col)))
    (let* ((want (or goal-col (nth-value 1 (%cursor-line-col line-starts cursor))))
           (next-line (1+ line)))
      (multiple-value-bind (start end) (%line-range line-starts buffer next-line)
        (let* ((len (- end start))
               (new-cursor (+ start (min want len))))
          (values new-cursor want))))))

(defun %tty-draw (path buffer cursor top-line)
  (%tty-clear)
  (multiple-value-bind (rows cols) (%tty-terminal-size)
    (let* ((header-lines 2)
           (footer-lines 2)
           (content-lines (max 1 (- rows header-lines footer-lines)))
           (line-starts (%buffer-line-starts buffer)))
      (tty-write-string (format nil "clemacs tty: ~A~%" (or path "<buffer>")))
      (tty-write-string "~%")

      (multiple-value-bind (cursor-line cursor-col) (%cursor-line-col line-starts cursor)
        (let* ((max-top (max 0 (- (length line-starts) content-lines)))
               (top (min (max 0 top-line) max-top))
               (top (cond
                     ((< cursor-line top) cursor-line)
                     ((>= cursor-line (+ top content-lines)) (- cursor-line content-lines -1))
                     (t top))))
          (setf top (min (max 0 top) max-top))

          (dotimes (i content-lines)
            (let ((line (+ top i)))
              (if (>= line (length line-starts))
                  (progn
                    (%tty-clear-eol)
                    (tty-write-string "~%"))
                  (multiple-value-bind (start end) (%line-range line-starts buffer line)
                    (let* ((s (subseq buffer start end))
                           (vis (if (> (length s) cols) (subseq s 0 cols) s)))
                      (tty-write-string vis)
                      (%tty-clear-eol)
                      (tty-write-string "~%"))))))

          (tty-write-string "~%")
          (tty-write-string "C-x C-c quit  C-x C-s save  arrows/C-b/C-f/C-p/C-n move~%")

          (let* ((row (+ header-lines 1 (- cursor-line top)))
                 (col (min cols (1+ cursor-col))))
            (%tty-move-cursor row col))
          top)))))

(defun %tty-insert (buffer cursor ch)
  (values
   (concatenate 'string (subseq buffer 0 cursor) (string ch) (subseq buffer cursor))
   (1+ cursor)))

(defun %tty-backspace (buffer cursor)
  (if (<= cursor 0)
      (values buffer cursor)
      (values
       (concatenate 'string (subseq buffer 0 (1- cursor)) (subseq buffer cursor))
       (1- cursor))))

(defun %tty-save (path buffer)
  (unless path
    (tty-write-string "\a")
    (return-from %tty-save nil))
  (with-open-file (out path
                       :direction :output
                       :if-exists :supersede
                       :if-does-not-exist :create
                       :external-format :utf-8)
    (write-string buffer out))
  t)

(defun %tty-read-escape ()
  (let ((b1 (tty-read-byte)))
    (if (= b1 91) ; [
        (tty-read-byte)
        b1)))

(defun tty-main (&key path)
  (let* ((path* (and path (not (string= path "")) path))
         (buffer (if (and path* (probe-file path*))
                     (uiop:read-file-string path* :external-format :utf-8)
                     ""))
         (cursor (length buffer))
         (top-line 0)
         (goal-col nil))
    (unwind-protect
        (progn
          (tty-enter-raw)
          (loop
            (setf top-line (%tty-draw path* buffer cursor top-line))
            (let ((b (tty-read-byte)))
              (cond
               ((= b 17) ; C-q
                (return 0))
               ((= b 24) ; C-x prefix
                (let ((b2 (tty-read-byte)))
                  (cond
                   ((= b2 3) ; C-c
                    (return 0))
                   ((= b2 19) ; C-s
                    (unless (%tty-save path* buffer)
                      (tty-write-string "\a")))
                   (t nil))))
               ((= b 19) ; C-s
                (unless (%tty-save path* buffer)
                  (tty-write-string "\a")))
               ((= b 2) ; C-b
                (setf cursor (max 0 (1- cursor)))
                (setf goal-col nil))
               ((= b 6) ; C-f
                (setf cursor (min (length buffer) (1+ cursor)))
                (setf goal-col nil))
               ((= b 16) ; C-p
                (multiple-value-setq (cursor goal-col)
                  (%tty-move-up buffer (%buffer-line-starts buffer) cursor goal-col)))
               ((= b 14) ; C-n
                (multiple-value-setq (cursor goal-col)
                  (%tty-move-down buffer (%buffer-line-starts buffer) cursor goal-col)))
               ((or (= b 8) (= b 127)) ; backspace
                (multiple-value-setq (buffer cursor) (%tty-backspace buffer cursor))
                (setf goal-col nil))
               ((= b 27) ; ESC sequence
                (let ((esc3 (%tty-read-escape)))
                  (case esc3
                    (68 (setf cursor (max 0 (1- cursor)))
                        (setf goal-col nil)) ; left
                    (67 (setf cursor (min (length buffer) (1+ cursor)))
                        (setf goal-col nil)) ; right
                    (65 (multiple-value-setq (cursor goal-col)
                          (%tty-move-up buffer (%buffer-line-starts buffer) cursor goal-col))) ; up
                    (66 (multiple-value-setq (cursor goal-col)
                          (%tty-move-down buffer (%buffer-line-starts buffer) cursor goal-col))) ; down
                    (t nil))))
               ((or (= b 10) (= b 13)) ; enter
                (multiple-value-setq (buffer cursor) (%tty-insert buffer cursor #\Newline))
                (setf goal-col nil))
               ((and (<= 32 b) (<= b 126))
                (multiple-value-setq (buffer cursor) (%tty-insert buffer cursor (code-char b)))
                (setf goal-col nil))
               (t nil))))))
      (ignore-errors (tty-exit-raw))
      (%tty-clear)))
