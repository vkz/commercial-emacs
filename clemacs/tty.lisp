(in-package #:clemacs)

(defun %tty-clear ()
  (tty-write-string (format nil "~C[2J~C[H" #\Esc #\Esc)))

(defun %tty-move-cursor (row col)
  (tty-write-string (format nil "~C[~D;~DH" #\Esc row col)))

(defun %tty-draw (path buffer cursor)
  (%tty-clear)
  (tty-write-string (format nil "clemacs tty: ~A~%~%" (or path "<buffer>")))
  (tty-write-string buffer)
  (tty-write-string "~%~%C-q quit  C-s save  C-b/C-f move~%")

  (let* ((header-lines 2)
         (cursor-base-row (+ 1 header-lines))
         (cursor-base-col 1)
         (before (subseq buffer 0 (min cursor (length buffer))))
         (line (count #\Newline before))
         (last-nl (position #\Newline before :from-end t))
         (col (if last-nl (- (length before) last-nl) (1+ (length before))))
         (row (+ cursor-base-row line)))
    (%tty-move-cursor row (+ cursor-base-col (1- col)))))

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
         (cursor (length buffer)))
    (unwind-protect
        (progn
          (tty-enter-raw)
          (loop
            (%tty-draw path* buffer cursor)
            (let ((b (tty-read-byte)))
              (cond
               ((= b 17) ; C-q
                (return 0))
               ((= b 19) ; C-s
                (unless (%tty-save path* buffer)
                  (tty-write-string "\a")))
               ((= b 2) ; C-b
                (setf cursor (max 0 (1- cursor))))
               ((= b 6) ; C-f
                (setf cursor (min (length buffer) (1+ cursor))))
               ((or (= b 8) (= b 127)) ; backspace
                (multiple-value-setq (buffer cursor) (%tty-backspace buffer cursor)))
               ((= b 27) ; ESC sequence
                (let ((esc3 (%tty-read-escape)))
                  (case esc3
                    (68 (setf cursor (max 0 (1- cursor)))) ; left
                    (67 (setf cursor (min (length buffer) (1+ cursor)))) ; right
                    (t nil))))
               ((or (= b 10) (= b 13)) ; enter
                (multiple-value-setq (buffer cursor) (%tty-insert buffer cursor #\Newline)))
               ((and (<= 32 b) (<= b 126))
                (multiple-value-setq (buffer cursor) (%tty-insert buffer cursor (code-char b))))
               (t nil))))))
      (ignore-errors (tty-exit-raw))
      (%tty-clear)))
