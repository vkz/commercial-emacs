(in-package #:clemacs)

(defstruct (buffer
            (:constructor %make-buffer (&key (path nil) (text "") (point 0))))
  (path nil :type (or null string))
  (text "" :type string)
  (point 0 :type fixnum))

(defun make-buffer (&key (content "") (path nil))
  (%make-buffer :path path :text content :point (length content)))

(defun buffer-length (buf)
  (length (buffer-text buf)))

(defun buffer-clamp-point (buf)
  (setf (buffer-point buf)
        (max 0 (min (buffer-point buf) (buffer-length buf))))
  buf)

(defun buffer-insert-char (buf ch)
  (let* ((text (buffer-text buf))
         (p (buffer-point buf)))
    (setf (buffer-text buf)
          (concatenate 'string (subseq text 0 p) (string ch) (subseq text p)))
    (incf (buffer-point buf))
    buf))

(defun buffer-insert-string (buf s)
  (let* ((text (buffer-text buf))
         (p (buffer-point buf)))
    (setf (buffer-text buf)
          (concatenate 'string (subseq text 0 p) s (subseq text p)))
    (incf (buffer-point buf) (length s))
    buf))

(defun buffer-delete-backward (buf)
  (let* ((p (buffer-point buf))
         (text (buffer-text buf)))
    (when (> p 0)
      (setf (buffer-text buf)
            (concatenate 'string (subseq text 0 (1- p)) (subseq text p)))
      (decf (buffer-point buf)))
    buf))

(defun buffer-forward-char (buf)
  (incf (buffer-point buf))
  (buffer-clamp-point buf))

(defun buffer-backward-char (buf)
  (decf (buffer-point buf))
  (buffer-clamp-point buf))

(defun %line-starts (text)
  (let ((starts (list 0)))
    (loop for i from 0 below (length text) do
      (when (char= (aref text i) #\Newline)
        (push (1+ i) starts)))
    (coerce (nreverse starts) 'vector)))

(defun %line-number-at (line-starts point)
  (let ((n (length line-starts))
        (best 0))
    (dotimes (i n best)
      (let ((start (aref line-starts i)))
        (when (> start point)
          (return best))
        (setf best i)))))

(defun buffer-line-column (buf)
  (let* ((text (buffer-text buf))
         (p (buffer-point buf))
         (starts (%line-starts text))
         (line (%line-number-at starts p))
         (start (aref starts line)))
    (values line (- p start))))

(defun buffer-move-vertical (buf delta &key goal-column)
  (let* ((text (buffer-text buf))
         (starts (%line-starts text)))
    (multiple-value-bind (line col) (buffer-line-column buf)
      (let* ((want (or goal-column col))
             (target (max 0 (min (+ line delta) (1- (length starts))))))
        (let* ((start (aref starts target))
               (end (if (< (1+ target) (length starts))
                        (aref starts (1+ target))
                        (length text)))
               (end* (if (and (> end start) (char= (aref text (1- end)) #\Newline))
                         (1- end)
                         end))
               (len (- end* start))
               (new-point (+ start (min want len))))
          (setf (buffer-point buf) new-point)
          (values buf want))))))

(defun buffer-load-file (path)
  (let* ((content (if (probe-file path)
                      (uiop:read-file-string path :external-format :utf-8)
                      "")))
    (make-buffer :content content :path path)))

(defun buffer-save (buf)
  (let ((path (buffer-path buf)))
    (unless path
      (return-from buffer-save nil))
    (with-open-file (out path
                         :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create
                         :external-format :utf-8)
      (write-string (buffer-text buf) out))
    t))
