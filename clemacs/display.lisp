(in-package #:clemacs)

(defstruct (grid-frame
            (:constructor make-grid-frame
                (&key rows cols lines cursor-row cursor-col scroll-from-row scroll-to-row)))
  "Backend-neutral grid representation for rendering.

This is intentionally small: it provides an API boundary between editor state
and any renderer (TTY today, browser later)."
  (rows 0 :type fixnum)
  (cols 0 :type fixnum)
  ;; Vector indexed by 0-based row (row 1 -> index 0). Each entry is a string
  ;; to render on that row (without a trailing newline).
  (lines #() :type vector)
  ;; Optional 1-based scroll region bounds for :scroll patches.  When NIL, the
  ;; renderer should treat :scroll as unsupported and fall back to :put-row.
  (scroll-from-row nil :type (or null fixnum))
  (scroll-to-row nil :type (or null fixnum))
  ;; 1-based cursor position.
  (cursor-row 1 :type fixnum)
  (cursor-col 1 :type fixnum))

(defun make-empty-grid-frame (rows cols)
  (make-grid-frame
   :rows rows
   :cols cols
   :lines (make-array rows :initial-element "")
   :scroll-from-row nil
   :scroll-to-row nil
   :cursor-row 1
   :cursor-col 1))

(defvar *grid-patch-sinks* nil
  "Optional list of functions invoked with (OPS FRAME PREV) after patch compute.")

(defun %json-escape-string (s)
  (with-output-to-string (out)
    (write-char #\" out)
    (loop for ch across s do
      (case ch
        (#\" (write-string "\\\"" out))
        (#\\ (write-string "\\\\" out))
        (#\Newline (write-string "\\n" out))
        (#\Return (write-string "\\r" out))
        (#\Tab (write-string "\\t" out))
        (t
         (let ((code (char-code ch)))
           (if (or (< code 32) (= code 127))
               (format out "\\u~4,'0x" code)
               (write-char ch out))))))
    (write-char #\" out)))

(defun %write-json-value (v stream)
  (cond
   ((null v) (write-string "null" stream))
   ((integerp v) (write-string (princ-to-string v) stream))
   ((stringp v) (write-string (%json-escape-string v) stream))
   ((symbolp v)
    (write-string (%json-escape-string (string-downcase (symbol-name v))) stream))
   ((listp v)
    (write-char #\[ stream)
    (loop for x in v for firstp = t then nil do
      (unless firstp (write-string "," stream))
      (%write-json-value x stream))
    (write-char #\] stream))
   (t
    (write-string (%json-escape-string (prin1-to-string v)) stream))))

(defun %write-json-op (op stream)
  (write-char #\{ stream)
  (let ((firstp t))
    (loop for (k v) on op by #'cddr do
      (unless firstp (write-string "," stream))
      (setf firstp nil)
      (%write-json-value (string-downcase (symbol-name k)) stream)
      (write-string ":" stream)
      (%write-json-value v stream)))
  (write-char #\} stream))

(defun make-grid-patch-jsonl-sink (path)
  (lambda (ops frame _prev)
    (declare (ignore _prev))
    (with-open-file (s path :direction :output :if-exists :append :if-does-not-exist :create)
      (write-char #\{ s)
      (%write-json-value "rows" s) (write-string ":" s) (%write-json-value (grid-frame-rows frame) s)
      (write-string "," s)
      (%write-json-value "cols" s) (write-string ":" s) (%write-json-value (grid-frame-cols frame) s)
      (write-string "," s)
      (%write-json-value "cursor_row" s) (write-string ":" s) (%write-json-value (grid-frame-cursor-row frame) s)
      (write-string "," s)
      (%write-json-value "cursor_col" s) (write-string ":" s) (%write-json-value (grid-frame-cursor-col frame) s)
      (write-string "," s)
      (%write-json-value "ops" s) (write-string ":" s)
      (write-char #\[ s)
      (loop for op in ops for firstp = t then nil do
        (unless firstp (write-string "," s))
        (%write-json-op op s))
      (write-char #\] s)
      (write-char #\} s)
      (terpri s))))

(defun maybe-emit-grid-patch (ops frame prev)
  (dolist (sink *grid-patch-sinks*)
    (ignore-errors
      (funcall sink ops frame prev))))

(defun grid-frame->patch (frame &optional prev)
  "Compute a renderer-neutral patch from PREV to FRAME.

The patch is a list of plists with an :op key:
- (:op :clear)                     Clear the full viewport.
- (:op :put-row :row N :text TEXT) Replace a 1-based row with TEXT.
- (:op :scroll :from A :to B :n K) Scroll rows A..B by K (positive = down).
- (:op :clear-eol :row R :col C)   Clear from 1-based R,C to end-of-line.
- (:op :set-cursor :row R :col C)  Move cursor to 1-based R,C.

Notes:
- This emits :scroll when a simple row-shift can be detected inside the
  frame's declared scroll region."
  (let ((ops nil))
    (labels ((emit (plist) (push plist ops))
             (same-shape-p (a b)
               (and a b
                    (= (grid-frame-rows a) (grid-frame-rows b))
                    (= (grid-frame-cols a) (grid-frame-cols b))
                    (= (length (grid-frame-lines a))
                       (length (grid-frame-lines b)))))
             (vis (s cols)
               (let ((s (or s "")))
                 (if (and (stringp s) (> (length s) cols))
                     (subseq s 0 cols)
                     s))))
      (unless (same-shape-p frame prev)
        (emit (list :op :clear)))
      (let* ((rows (grid-frame-rows frame))
             (cols (grid-frame-cols frame))
             (from (grid-frame-scroll-from-row frame))
             (to (grid-frame-scroll-to-row frame))
             (scroll-k 0)
             (do-scroll nil))
        (when (and (same-shape-p frame prev)
                   (integerp from) (integerp to)
                   (integerp (grid-frame-scroll-from-row prev))
                   (integerp (grid-frame-scroll-to-row prev))
                   (= from (grid-frame-scroll-from-row prev))
                   (= to (grid-frame-scroll-to-row prev))
                   (<= 1 from to rows))
          (let* ((h (1+ (- to from)))
                 (new (map 'vector
                           (lambda (s) (vis s cols))
                           (subseq (grid-frame-lines frame) (1- from) to)))
                 (old (map 'vector
                           (lambda (s) (vis s cols))
                           (subseq (grid-frame-lines prev) (1- from) to)))
                 (best-k 0)
                 (best-m 0)
                 (best-overlap 0))
            (when (> h 2)
              (loop for k from (- h 1) to (1- h) do
                (unless (zerop k)
                  (let ((m 0))
                    (dotimes (i h)
                      (let ((j (- i k)))
                        (when (and (<= 0 j) (< j h)
                                   (equal (aref new i) (aref old j)))
                          (incf m))))
                    (let ((overlap (- h (abs k))))
                      (when (or (> m best-m)
                                (and (= m best-m)
                                     (or (> overlap best-overlap)
                                         (and (= overlap best-overlap)
                                              (< (abs k) (abs best-k))))))
                        (setf best-m m
                              best-k k
                              best-overlap overlap)))))))
            (let* ((max-overlap (- h (abs best-k)))
                   (ratio (if (<= max-overlap 0) 0 (/ best-m max-overlap)))
                   ;; Heuristic:
                   ;; - Require >=2 lines of overlap.
                   ;; - For small overlaps (2..4), require perfect overlap match.
                   ;; - For larger overlaps, require a high match ratio.
                   (okp (and (not (zerop best-k))
                             (>= max-overlap 2)
                             (or (and (<= max-overlap 4) (= best-m max-overlap))
                                 (and (>= max-overlap 5) (>= ratio 3/4))))))
              (when okp
                (setf do-scroll t
                      scroll-k best-k)
                (emit (list :op :scroll :from from :to to :n scroll-k))))))

        (dotimes (i rows)
          (let* ((row (1+ i))
                 (text (vis (aref (grid-frame-lines frame) i) cols))
                 (prev-text
                   (and prev
                        (< i (length (grid-frame-lines prev)))
                        (vis (aref (grid-frame-lines prev) i) cols))))
            (cond
             ((null prev)
              (emit (list :op :put-row :row row :text text)))
             ((and do-scroll (<= from row to))
              (let* ((ii (- row from))
                     (jj (- ii scroll-k))
                     (expected
                       (if (and (<= 0 jj) (< jj (1+ (- to from))))
                           (vis (aref (grid-frame-lines prev) (+ (1- from) jj)) cols)
                           "")))
                (cond
                 ((equal text expected) nil)
                 ((and (stringp expected) (stringp text)
                       (< (length text) (length expected))
                       (string= text expected :end2 (length text)))
                  (emit (list :op :clear-eol :row row :col (1+ (length text)))))
                 (t
                  (emit (list :op :put-row :row row :text text))))))
             ((not (equal text prev-text))
              (cond
               ((and (stringp prev-text) (stringp text)
                     (< (length text) (length prev-text))
                     (string= text prev-text :end2 (length text)))
                (emit (list :op :clear-eol :row row :col (1+ (length text)))))
               (t
                (emit (list :op :put-row :row row :text text))))))))
      (emit (list :op :set-cursor
                  :row (grid-frame-cursor-row frame)
                  :col (grid-frame-cursor-col frame))))
    (setf ops (nreverse ops))
    (maybe-emit-grid-patch ops frame prev)
    ops)))
