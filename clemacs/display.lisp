(in-package #:clemacs)

(defstruct (grid-frame
            (:constructor make-grid-frame
                (&key rows cols lines cursor-row cursor-col)))
  "Backend-neutral grid representation for rendering.

This is intentionally small: it provides an API boundary between editor state
and any renderer (TTY today, browser later)."
  (rows 0 :type fixnum)
  (cols 0 :type fixnum)
  ;; Vector indexed by 0-based row (row 1 -> index 0). Each entry is a string
  ;; to render on that row (without a trailing newline).
  (lines #() :type vector)
  ;; 1-based cursor position.
  (cursor-row 1 :type fixnum)
  (cursor-col 1 :type fixnum))

(defun make-empty-grid-frame (rows cols)
  (make-grid-frame
   :rows rows
   :cols cols
   :lines (make-array rows :initial-element "")
   :cursor-row 1
   :cursor-col 1))

(defun grid-frame->patch (frame &optional prev)
  "Compute a renderer-neutral patch from PREV to FRAME.

The patch is a list of plists with an :op key:
- (:op :clear)                     Clear the full viewport.
- (:op :put-row :row N :text TEXT) Replace a 1-based row with TEXT.
- (:op :scroll :from A :to B :n K) Scroll rows A..B by K (positive = down).
- (:op :set-cursor :row R :col C)  Move cursor to 1-based R,C.

Notes:
- This currently emits only :clear, :put-row, and :set-cursor.
- The :scroll op is part of the stable protocol but is not yet produced."
  (let ((ops nil))
    (labels ((emit (plist) (push plist ops))
             (same-shape-p (a b)
               (and a b
                    (= (grid-frame-rows a) (grid-frame-rows b))
                    (= (grid-frame-cols a) (grid-frame-cols b))
                    (= (length (grid-frame-lines a))
                       (length (grid-frame-lines b))))))
      (unless (same-shape-p frame prev)
        (emit (list :op :clear)))
      (dotimes (i (grid-frame-rows frame))
        (let* ((row (1+ i))
               (text (aref (grid-frame-lines frame) i))
               (prev-text
                 (and prev
                      (< i (length (grid-frame-lines prev)))
                      (aref (grid-frame-lines prev) i))))
          (when (or (null prev) (not (equal text prev-text)))
            (emit (list :op :put-row :row row :text text)))))
      (emit (list :op :set-cursor
                  :row (grid-frame-cursor-row frame)
                  :col (grid-frame-cursor-col frame))))
    (nreverse ops)))
