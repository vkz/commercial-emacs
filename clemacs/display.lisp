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
