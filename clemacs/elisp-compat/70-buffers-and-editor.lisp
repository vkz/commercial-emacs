(in-package #:elisp)

;; ---------------------------------------------------------------------------
;; Minimal buffer/marker surface (enough for upstream ERT bring-up)
;; ---------------------------------------------------------------------------

(cl:defvar enable-multibyte-characters t)
(cl:defvar selective-display nil)

(cl:defun set-buffer-multibyte (flag)
  "Bring-up subset of the C primitive `set-buffer-multibyte'.

This does not convert buffer contents; it only updates
`enable-multibyte-characters` for the current buffer."
  (make-local-variable 'enable-multibyte-characters)
  (set 'enable-multibyte-characters (and flag t)))

(defstruct elisp-marker-edit
  ;; :insert  a=at  b=len
  ;; :delete  a=start  b=end
  (kind :insert :type keyword)
  (a 0 :type integer)
  (b 0 :type integer))

(defstruct elisp-buffer
  (name "" :type (or cl:string unibyte-string))
  (text "" :type cl:string)
  (point 1 :type integer)
  (modified-p nil :type boolean)
  ;; Narrowing is represented as a half-open restriction interval in ELisp
  ;; buffer coordinates (point-min <= point <= point-max).  When nil, the
  ;; corresponding side is unbounded (i.e. 1 / (1+ (length text))).
  (restriction-min nil :type (or null integer))
  (restriction-max nil :type (or null integer))
  (syntax-table nil)
  (locals (cl:make-hash-table :test 'eq) :type hash-table)
  ;; Weak registry of markers attached to this buffer (for edit-log compaction).
  (markers #+sbcl (make-hash-table :test 'eq :weakness :key)
           #-sbcl (make-hash-table :test 'eq)
           :type hash-table)
  (marker-edits (make-array 0 :adjustable t :fill-pointer 0) :type vector)
  (overlays nil))

(defstruct elisp-marker
  (buffer nil)
  (position nil)
  ;; If true, the marker advances when text is inserted at its position.
  (insertion-type nil)
  ;; Number of buffer edits already applied to POSITION.
  (edit-index 0 :type integer))

(defparameter +marker-edit-compact-threshold+ 256)

(cl:defun %buffer-register-marker (buffer marker)
  (when (and (elisp-buffer-p buffer) (elisp-marker-p marker))
    (setf (gethash marker (elisp-buffer-markers buffer)) t))
  marker)

(cl:defun %buffer-unregister-marker (buffer marker)
  (when (and (elisp-buffer-p buffer) (elisp-marker-p marker))
    (remhash marker (elisp-buffer-markers buffer)))
  marker)

(cl:defun %buffer-maybe-compact-marker-edits (buffer)
  (let* ((edits (elisp-buffer-marker-edits buffer))
         (n (fill-pointer edits)))
    (when (> n +marker-edit-compact-threshold+)
      ;; Bring all live markers up-to-date, then clear the edit log.
      (maphash
       (lambda (m _)
         (declare (cl:ignore _))
         (%marker-sync m)
         (setf (elisp-marker-edit-index m) 0))
       (elisp-buffer-markers buffer))
      (setf (fill-pointer edits) 0)))
  nil)

(cl:defun %buffer-record-insert (buffer at len)
  (when (plusp len)
    (when (elisp-buffer-p buffer)
      (setf (elisp-buffer-modified-p buffer) t))
    (vector-push-extend (make-elisp-marker-edit :kind :insert :a at :b len)
                        (elisp-buffer-marker-edits buffer)))
  (%buffer-maybe-compact-marker-edits buffer)
  nil)

(cl:defun %buffer-record-delete (buffer start end)
  (let ((len (- end start)))
    (when (plusp len)
      (when (elisp-buffer-p buffer)
        (setf (elisp-buffer-modified-p buffer) t))
      (vector-push-extend (make-elisp-marker-edit :kind :delete :a start :b end)
                          (elisp-buffer-marker-edits buffer))))
  (%buffer-maybe-compact-marker-edits buffer)
  nil)

(cl:defun %marker-sync (marker)
  (let* ((buf (elisp-marker-buffer marker))
         (pos (elisp-marker-position marker)))
    (when (and (elisp-buffer-p buf) (integerp pos))
      (let* ((edits (elisp-buffer-marker-edits buf))
             (n (fill-pointer edits))
             (i (min (elisp-marker-edit-index marker) n)))
        (loop for idx from i below n do
          (let* ((e (aref edits idx))
                 (kind (elisp-marker-edit-kind e)))
            (ecase kind
              (:insert
               (let ((at (elisp-marker-edit-a e))
                     (len (elisp-marker-edit-b e)))
                 (when (or (> pos at)
                           (and (= pos at) (elisp-marker-insertion-type marker)))
                   (incf pos len))))
              (:delete
               (let ((start (elisp-marker-edit-a e))
                     (end (elisp-marker-edit-b e))
                     (len (- (elisp-marker-edit-b e) (elisp-marker-edit-a e))))
                 (cond
                  ((> pos end) (decf pos len))
                  ((>= pos start) (setf pos start)))))))
        ;; Keep marker positions within buffer bounds.  Emacs clamps positions,
        ;; and allowing markers to drift past point-max can lead to infinite
        ;; loops in code that uses an end-marker as a moving boundary (pp.el).
        (let ((pmax (1+ (length (elisp-buffer-text buf)))))
          (setf pos (max 1 (min pos pmax))))
        (setf (elisp-marker-position marker) pos
              (elisp-marker-edit-index marker) n))))
  marker))

(cl:defun %buffer-edit-index (buffer)
  (fill-pointer (elisp-buffer-marker-edits buffer)))

(cl:defun make-marker ()
  "Bring-up subset of ELisp `make-marker'.

Returns a marker with no buffer/position."
  (make-elisp-marker))

(cl:defun markerp (x)
  (elisp-marker-p x))

(cl:defun marker-position (marker)
  "Bring-up subset of ELisp `marker-position'."
  (unless (elisp-marker-p marker)
    (error "ELISP:MARKER-POSITION expected marker, got: ~S" marker))
  (elisp-marker-position (%marker-sync marker)))

(defvar *buffer-table* (cl:make-hash-table :test 'cl:equal))
(defvar *buffer-list* nil)

(cl:defun %initial-default-directory ()
  (let* ((cwd (uiop:getcwd))
         (p (etypecase cwd
              (pathname (uiop:ensure-directory-pathname cwd))
              (cl:string (uiop:ensure-directory-pathname cwd)))))
    (namestring p)))

(cl:defvar default-directory (%initial-default-directory))

(cl:defun %buffer-name-key (name)
  ;; Keep buffer table keys as CL strings so CL:EQUAL hashing works even when
  ;; ELisp passes us unibyte strings.
  (%elisp-string->cl-string name))

(cl:defun %register-buffer (buf)
  (setf (gethash (%buffer-name-key (elisp-buffer-name buf)) *buffer-table*) buf)
  (unless (cl:member buf *buffer-list* :test #'eq)
    ;; Keep creation order stable; selection is tracked separately.
    (setf *buffer-list* (append *buffer-list* (list buf))))
  buf)

(cl:defvar *current-buffer* (%register-buffer (make-elisp-buffer :name "*Messages*")))
(defparameter message-log-max t)

(cl:defun current-buffer ()
  *current-buffer*)

(cl:defun bufferp (x)
  "Bring-up subset of ELisp `bufferp'."
  (elisp-buffer-p x))

(cl:defun messages-buffer ()
  "Bring-up subset of ELisp `messages-buffer'.

Return the current *Messages* buffer (creating it if needed)."
  (get-buffer-create "*Messages*"))

(cl:defvar *killed-buffers* (cl:make-hash-table :test 'eq))

(cl:defun %buffer-live-p (buf)
  (and (elisp-buffer-p buf)
       (not (gethash buf *killed-buffers*))))

(cl:defun buffer-live-p (buffer)
  "Bring-up subset of ELisp `buffer-live-p'."
  (let ((buf (etypecase buffer
               (elisp-buffer buffer)
               ((or cl:string unibyte-string) (get-buffer buffer))
               (null nil))))
    (and buf (%buffer-live-p buf) t)))

;; ---------------------------------------------------------------------------
;; Syntax tables / indentation (minimal stubs for pp.el bring-up)
;; ---------------------------------------------------------------------------

(cl:defvar emacs-lisp-mode-syntax-table :emacs-lisp-mode-syntax-table)

(cl:defun syntax-table ()
  "Bring-up stub for ELisp `syntax-table'."
  (elisp-buffer-syntax-table *current-buffer*))

(cl:defun set-syntax-table (table)
  "Bring-up stub for ELisp `set-syntax-table'."
  (setf (elisp-buffer-syntax-table *current-buffer*) table)
  table)

(cl:defmacro with-syntax-table (table &body body)
  "Bring-up stub for ELisp `with-syntax-table'."
  (let ((old (cl:gensym "OLD-SYNTAX-TABLE-")))
    `(let ((,old (syntax-table)))
       (unwind-protect
           (progn
             (set-syntax-table ,table)
             ,@body)
         (set-syntax-table ,old)))))

(cl:defun syntax-ppss (&optional pos)
  "Bring-up subset of ELisp `syntax-ppss' for Emacs Lisp buffers.

Returns an Emacs-style parse state list (11 elements), computed via the
compat `parse-partial-sexp' scanner.

Note: Like Emacs, this has a point-moving side effect when POS differs from
the current point (because it delegates to `parse-partial-sexp')."
  (let ((p (%pos (or pos (point)))))
    (parse-partial-sexp (point-min) p)))

(cl:defvar indent-line-function nil)

(cl:defun lisp-mode-variables (&optional _arg)
  "Bring-up stub for ELisp `lisp-mode-variables'."
  (declare (cl:ignore _arg))
  (setf indent-line-function #'lisp-indent-line)
  nil)

(cl:defun emacs-lisp-mode ()
  "Bring-up stub for ELisp `emacs-lisp-mode'."
  (setf major-mode 'emacs-lisp-mode)
  (set-syntax-table emacs-lisp-mode-syntax-table)
  ;; Ensure the local keymap has a `[menu-bar]' prefix keymap so upstream ERT
  ;; (subr-test-local-key-binding) can probe menu bindings without loading the
  ;; full major mode machinery yet.
  (let* ((menu-bar-submap (list 'keymap nil (make-elisp-keymap)))
         (km (list 'keymap nil (make-elisp-keymap))))
    (setf (gethash 'menu-bar (elisp-keymap-table (caddr km))) menu-bar-submap)
    (cond
     ((fboundp 'use-local-map) (use-local-map km))
     (t (setf (cl:symbol-value 'local-map) km))))
  (lisp-mode-variables)
  nil)

(cl:defun lisp-indent-line ()
  "Bring-up subset of ELisp `lisp-indent-line'.

This is a small indentation model sufficient for pp.el/ERT bring-up."
  (let* ((txt (elisp-buffer-text *current-buffer*))
         (idx (1- (point)))
         (nl (cl:position #\Newline txt :end idx :from-end t))
         (line-start (if nl (+ nl 2) (point-min)))
         (saved (point)))
    (labels ((ws-p (ch)
               (or (char= ch #\Space)
                   (char= ch #\Tab)
                   (char= ch #\Newline)
                   (char= ch #\Return)))
             (peek (p)
               (when (and (<= (point-min) p) (< p (point-max)))
                 (char (elisp-buffer-text *current-buffer*) (1- p))))
             (skip-ws (p &optional (limit (point-max)))
               (loop for pos = p then (1+ pos)
                     while (< pos limit)
                     for ch = (peek pos)
                     while (and ch (ws-p ch))
                     finally (return pos)))
             (column-at-pos (p)
               (let ((p0 (point)))
                 (unwind-protect
                     (progn (goto-char p) (current-column))
                   (goto-char p0))))
             (strip-indentation ()
               (goto-char line-start)
               (skip-chars-forward (coerce (list #\Space #\Tab) 'cl:string))
               (let ((nonws (point)))
                 (when (> nonws line-start)
                   (delete-region line-start nonws)
                   (let ((deleted (- nonws line-start)))
                     (setf saved
                           (cond
                            ((<= saved nonws) line-start)
                            (t (- saved deleted))))))))
             (indent-to (n)
               (strip-indentation)
               (goto-char line-start)
               (when (plusp n)
                 (insert (cl:make-string n :initial-element #\Space))
                 (when (>= saved line-start)
                   (incf saved n)))
               (goto-char (min (point-max) (max line-start saved))))
             (find-containing-open-paren (p)
               (let ((depth 0)
                     (open nil))
                 (loop for i downfrom (1- p) downto (point-min) do
                   (let ((ch (peek i)))
                     (cond
                      ((null ch) (return))
                      ((char= ch #\)) (incf depth))
                      ((char= ch #\() (if (zerop depth)
                                          (progn (setf open i) (return))
                                          (decf depth))))))
                 open))
             (line-leading-char ()
               (peek (skip-ws line-start)))
             (token-starts-with-colon-p (p)
               (let ((ch (peek p)))
                 (and ch (char= ch #\:)))))
      (let* ((open (find-containing-open-paren line-start))
             (indent-col 0))
        (cond
         ((null open)
          (setf indent-col 0))
         ((let ((ch (line-leading-char)))
            (and ch (char= ch #\))))
          (setf indent-col (column-at-pos open)))
         (t
          (let* ((open-col (column-at-pos open))
                 (head-start (skip-ws (1+ open) line-start)))
            (if (>= head-start line-start)
                (setf indent-col (1+ open-col))
                (let* ((head-end (or (scan-sexps head-start 1) head-start))
                       (arg1 (skip-ws head-end))
                       (head-sym
                         (when (and (< head-start line-start)
                                    (integerp head-end)
                                    (> head-end head-start))
                           (let ((token (subseq txt (1- head-start) (1- head-end))))
                             (ignore-errors (intern-soft token)))))
                       ;; Emacs distinguishes between function calls and "data
                       ;; lists": when the head symbol is not fboundp, indent
                       ;; like a plain list (open-col+1).  This matters for
                       ;; upstream ERT output (e.g. `ert-test-failed').
                       (head-fn-like-p (and head-sym (fboundp head-sym))))
                  (cond
                   ((or (null arg1) (>= arg1 (point-max)))
                    (setf indent-col (+ open-col 2)))
                   ((token-starts-with-colon-p head-start)
                    ;; Plist / keyword lists: indent continuation lines to the
                    ;; column of the first value, matching Emacs Lisp's
                    ;; `lisp-indent-line' behavior (pp.el relies on this).
                    (setf indent-col (column-at-pos arg1)))
                   ((>= arg1 line-start)
                    (setf indent-col (+ open-col (if head-fn-like-p 2 1))))
                   (t
                    (setf indent-col (column-at-pos arg1)))))))))
        (indent-to indent-col)
        nil))))

(cl:defun indent-region (start end &optional _column)
  "Bring-up subset of ELisp `indent-region'."
  (declare (cl:ignore _column))
  (unless (and (integerp start) (integerp end))
    (error "ELISP:INDENT-REGION expected integer bounds, got: ~S ~S" start end))
  (let ((fn (or indent-line-function #'lisp-indent-line))
        (end* (min end (point-max))))
    (let ((saved-buf (current-buffer))
          (saved-point (point)))
      (unwind-protect
          (progn
            (goto-char start)
            (beginning-of-line)
            (loop while (< (point) end*) do
              (funcall fn)
              (let ((p (point)))
                (forward-line 1)
                (when (<= (point) p)
                  (return)))))
        (set-buffer saved-buf)
        (goto-char saved-point))))
  nil)

(cl:defun get-buffer (buffer-or-name)
  "Bring-up subset of ELisp `get-buffer'."
  (etypecase buffer-or-name
    (elisp-buffer (and (%buffer-live-p buffer-or-name) buffer-or-name))
    ((or cl:string unibyte-string)
     (gethash (%buffer-name-key buffer-or-name) *buffer-table*))
    (null nil)))

(cl:defun get-buffer-create (name &optional _inhibit-buffer-hooks)
  "Bring-up subset of ELisp `get-buffer-create'."
  (declare (cl:ignore _inhibit-buffer-hooks))
  (unless (stringp name)
    (error "ELISP:GET-BUFFER-CREATE expects a string name, got: ~S" name))
  (or (gethash (%buffer-name-key name) *buffer-table*)
      (%register-buffer (make-elisp-buffer :name name))))

(cl:defun buffer-list (&optional _frame)
  "Bring-up subset of ELisp `buffer-list'."
  (declare (cl:ignore _frame))
  ;; Ensure we don't hand out dead buffers and keep current first.
  (let* ((live (remove-if-not #'%buffer-live-p *buffer-list*))
         (cur (current-buffer)))
    (if (and (%buffer-live-p cur) (cl:member cur live :test #'eq))
        (cons cur (remove cur live :test #'eq))
        live)))

(cl:defun other-buffer (&optional buffer _visible-ok _frame)
  "Bring-up subset of the C primitive `other-buffer'.

Return a live buffer other than BUFFER (default: current buffer).  This ignores
VISIBILE-OK and FRAME during bring-up."
  (declare (cl:ignore _visible-ok _frame))
  (let* ((cur (or (and (bufferp buffer) buffer) (current-buffer))))
    (dolist (b (buffer-list) cur)
      (when (and (bufferp b) (%buffer-live-p b) (not (eq b cur)))
        (return b)))))

(cl:defun find-buffer (variable value)
  "Bring-up subset of the C primitive `find-buffer'."
  (unless (symbolp variable)
    (error "ELISP:FIND-BUFFER expected symbol VARIABLE, got: ~S" variable))
  (dolist (buf (buffer-list) nil)
    (when (equal value (buffer-local-value variable buf))
      (return buf))))

(cl:defun %buffer-bump-to-front (buf)
  (when (and (elisp-buffer-p buf) (%buffer-live-p buf))
    (setf *buffer-list* (cons buf (remove buf *buffer-list* :test #'eq))))
  buf)

(cl:defun generate-new-buffer-name (name &optional _ignore)
  "Bring-up subset of ELisp `generate-new-buffer-name'."
  (declare (cl:ignore _ignore))
  (unless (stringp name)
    (error "ELISP:GENERATE-NEW-BUFFER-NAME expects a string, got: ~S" name))
  (if (null (gethash (%buffer-name-key name) *buffer-table*))
      name
      (loop for n from 2 do
        (let* ((base (%elisp-string->cl-string name))
               (cand (cl:format nil "~A<~D>" base n)))
          (when (null (gethash cand *buffer-table*))
            (return (string-to-unibyte cand)))))))

(cl:defun clone-buffer (&optional newname _display-flag)
  "Bring-up subset of ELisp `clone-buffer'."
  (declare (cl:ignore _display-flag))
  (let* ((src (current-buffer))
         (name (or newname (generate-new-buffer-name (buffer-name src))))
         (buf (get-buffer-create name)))
    (setf (elisp-buffer-text buf) (copy-seq (elisp-buffer-text src))
          (elisp-buffer-point buf) (elisp-buffer-point src)
          (elisp-buffer-modified-p buf) (elisp-buffer-modified-p src))
    (%set-buffer-text-properties buf (%buffer-text-properties src))
    buf))

(cl:defun rename-buffer (newname &optional unique)
  "Bring-up subset of ELisp `rename-buffer'."
  (unless (stringp newname)
    (error "ELISP:RENAME-BUFFER expects a string, got: ~S" newname))
  (let* ((buf (current-buffer))
         (old (elisp-buffer-name buf))
         (target
           (cond
            ((and (stringp old) (string= (%elisp-string->cl-string old)
                                         (%elisp-string->cl-string newname)))
             old)
            (unique
             (generate-new-buffer-name newname))
            (t
             (let* ((key (%buffer-name-key newname))
                    (existing (gethash key *buffer-table*)))
               (when (and existing (not (eq existing buf)))
                 (error "ELISP:RENAME-BUFFER name already in use: ~S" newname))
               newname)))))
    (remhash (%buffer-name-key old) *buffer-table*)
    (setf (elisp-buffer-name buf) target)
    (%register-buffer buf)
    target))

(cl:defun kill-buffer (&optional buffer-or-name)
  "Bring-up subset of ELisp `kill-buffer'."
  (let* ((buf (or (and buffer-or-name (get-buffer buffer-or-name))
                  (and (null buffer-or-name) (current-buffer))
                  (and (stringp buffer-or-name)
                       (cl:string= (%elisp-string->cl-string buffer-or-name) "")
                       (current-buffer)))))
    (unless buf
      (return-from kill-buffer nil))
    (remhash (%buffer-name-key (elisp-buffer-name buf)) *buffer-table*)
    (setf *buffer-list* (remove buf *buffer-list* :test #'eq))
    (setf (gethash buf *killed-buffers*) t)
    (%clear-buffer-text-properties buf)
    (when (eq buf *current-buffer*)
      (setf *current-buffer*
            (or (find-if #'%buffer-live-p *buffer-list*)
                (%register-buffer (make-elisp-buffer :name "*scratch*")))))
    (when (and (boundp '*single-window*)
               (elisp-window-p *single-window*)
               (eq (elisp-window-buffer *single-window*) buf))
      (setf (elisp-window-buffer *single-window*) *current-buffer*))
    t))

(cl:defun bury-buffer (&optional buffer-or-name)
  "Bring-up subset of ELisp `bury-buffer' (single-window)."
  (let* ((buf (or (and buffer-or-name (get-buffer buffer-or-name))
                  (current-buffer))))
    (unless (bufferp buf)
      (error "ELISP:BURY-BUFFER expected buffer or name, got: ~S" buffer-or-name))
    (setf *buffer-list* (append (remove buf *buffer-list* :test #'eq) (list buf)))
    (when (eq buf (current-buffer))
      (let ((next (find-if (lambda (b) (and (elisp-buffer-p b) (%buffer-live-p b) (not (eq b buf))))
                           *buffer-list*)))
        (when next
          (set-buffer next))))
    nil))

(cl:defun set-buffer (buffer-or-name)
  "Bring-up subset of ELisp `set-buffer'."
  (let ((buf (or (get-buffer buffer-or-name)
                 (and (stringp buffer-or-name)
                      (error "ELISP:SET-BUFFER no such buffer: ~S" buffer-or-name))
                 (error "ELISP:SET-BUFFER invalid buffer: ~S" buffer-or-name))))
    (setf *current-buffer* buf)
    (%buffer-bump-to-front buf)
    buf))

(cl:defmacro with-current-buffer (buffer &body body)
  `(let ((*current-buffer* (or (get-buffer ,buffer) ,buffer)))
     ,@body))

(cl:defmacro with-temp-buffer (&body body)
  `(with-current-buffer (make-elisp-buffer :name " *temp*")
     ,@body))

(cl:defmacro save-current-buffer (&body body)
  (let ((saved (cl:gensym "SAVED-BUF-")))
    `(let ((,saved (current-buffer)))
       (unwind-protect
           (progn ,@body)
         (set-buffer ,saved)))))

(cl:defmacro save-window-excursion (&body body)
  (let ((cfg (cl:gensym "CFG-")))
    `(let ((,cfg (current-window-configuration)))
       (unwind-protect
           (progn ,@body)
         (set-window-configuration ,cfg)))))

(cl:defmacro save-excursion (&body body)
  "Bring-up subset of ELisp `save-excursion'."
  ;; Emacs restores point using a marker so buffer edits inside BODY don't
  ;; shift the restored position.  This matters for pp.el, which uses
  ;; `save-excursion' around insertions while scanning the same line.
  (let ((buf (cl:gensym "BUF-"))
        (pt (cl:gensym "PT-")))
    `(let* ((,buf (current-buffer))
            (,pt (point-marker)))
       (unwind-protect
           (progn ,@body)
         ;; Restore buffer and point (clamped by `goto-char'), then drop the
         ;; temporary marker so we don't accumulate marker registry entries.
         (set-buffer ,buf)
         (goto-char ,pt)
         (%buffer-unregister-marker ,buf ,pt)))))

(cl:defun prin1 (object &optional stream)
  "Bring-up subset of ELisp `prin1'.

STREAM may be a buffer."
  (let ((out (or stream standard-output (current-buffer))))
    (cond
     ((bufferp out)
      (with-current-buffer out
        (insert (prin1-to-string object))))
     ((eq out t)
      (write-string (prin1-to-string object) *standard-output*))
     ((streamp out)
      (write-string (prin1-to-string object) out))
     (t
      (error "ELISP:PRIN1 unsupported stream: ~S" out))))
  object)

(cl:defun princ (object &optional stream)
  "Bring-up subset of ELisp `princ'.

STREAM may be a buffer."
  (let ((out (or stream standard-output (current-buffer))))
    (cond
     ((bufferp out)
     (with-current-buffer out
        (typecase object
          (null nil)
          (cl:string (insert object))
          (unibyte-string (insert object))
          (t (insert (prin1-to-string object))))))
     ((eq out t)
      (typecase object
        (null nil)
        (cl:string (write-string object *standard-output*))
        (unibyte-string (write-string (%elisp-string->cl-string object) *standard-output*))
        (t (write-string (prin1-to-string object) *standard-output*))))
     ((streamp out)
      (typecase object
        (null nil)
        (cl:string (write-string object out))
        (unibyte-string (write-string (%elisp-string->cl-string object) out))
        (t (write-string (prin1-to-string object) out))))
     (t
      (error "ELISP:PRINC unsupported stream: ~S" out))))
  object)

(cl:defmacro with-output-to-string (&body body)
  "Bring-up subset of ELisp `with-output-to-string'."
  `(with-temp-buffer
     (let ((standard-output (current-buffer)))
       ,@body
       (buffer-string))))

(cl:defun point ()
  (elisp-buffer-point *current-buffer*))

(cl:defun point-marker ()
  "Bring-up subset of ELisp `point-marker'."
  (let ((m (make-elisp-marker :buffer *current-buffer*
                              :position (point)
                              :edit-index (%buffer-edit-index *current-buffer*))))
    (%buffer-register-marker *current-buffer* m)
    m))

(cl:defun copy-marker (marker &optional insertion-type)
  "Bring-up subset of ELisp `copy-marker'."
  (etypecase marker
    (elisp-marker
     (let* ((marker (%marker-sync marker))
            (buf (elisp-marker-buffer marker)))
       (let ((m (make-elisp-marker
                 :buffer buf
                 :position (elisp-marker-position marker)
                 :insertion-type (and insertion-type t)
                 :edit-index (if buf (%buffer-edit-index buf) 0))))
         (%buffer-register-marker buf m)
         m)))
    (integer
     (let ((m (make-elisp-marker :buffer *current-buffer*
                                 :position marker
                                 :insertion-type (and insertion-type t)
                                 :edit-index (%buffer-edit-index *current-buffer*))))
       (%buffer-register-marker *current-buffer* m)
       m))))

(cl:defun point-min ()
  (or (elisp-buffer-restriction-min *current-buffer*) 1))

(cl:defun point-max ()
  (or (elisp-buffer-restriction-max *current-buffer*)
      (1+ (length (elisp-buffer-text *current-buffer*)))))

(cl:defun buffer-narrowed-p ()
  "Bring-up subset of ELisp `buffer-narrowed-p'."
  (let* ((buf *current-buffer*)
         (abs-min 1)
         (abs-max (1+ (length (elisp-buffer-text buf))))
         (min (or (elisp-buffer-restriction-min buf) abs-min))
         (max (or (elisp-buffer-restriction-max buf) abs-max)))
    (or (/= min abs-min) (/= max abs-max) t)))

(cl:defun narrow-to-region (start end)
  "Bring-up subset of ELisp `narrow-to-region'."
  (let* ((buf *current-buffer*)
         (abs-min 1)
         (abs-max (1+ (length (elisp-buffer-text buf))))
         (a (%pos start))
         (b (%pos end))
         (min (min a b))
         (max (max a b))
         (min (max abs-min (min min abs-max)))
         (max (max abs-min (min max abs-max))))
    (setf (elisp-buffer-restriction-min buf) min
          (elisp-buffer-restriction-max buf) max)
    (setf (elisp-buffer-point buf) (max min (min (elisp-buffer-point buf) max)))
    nil))

(cl:defun widen ()
  "Bring-up subset of ELisp `widen'."
  (setf (elisp-buffer-restriction-min *current-buffer*) nil
        (elisp-buffer-restriction-max *current-buffer*) nil)
  nil)

(cl:defmacro save-restriction (&body body)
  "Bring-up subset of ELisp `save-restriction'."
  (let ((buf (cl:gensym "BUF-"))
        (min (cl:gensym "MIN-"))
        (max (cl:gensym "MAX-")))
    `(let* ((,buf *current-buffer*)
            (,min (elisp-buffer-restriction-min ,buf))
            (,max (elisp-buffer-restriction-max ,buf)))
       (unwind-protect
           (progn ,@body)
         (when (elisp-buffer-p ,buf)
           (let* ((abs-min 1)
                  (abs-max (1+ (length (elisp-buffer-text ,buf))))
                  (min* (or ,min abs-min))
                  (max* (or ,max abs-max))
                  (min* (max abs-min (min min* abs-max)))
                  (max* (max abs-min (min max* abs-max)))
                  (p (elisp-buffer-point ,buf)))
             (setf (elisp-buffer-restriction-min ,buf) ,min
                   (elisp-buffer-restriction-max ,buf) ,max
                   (elisp-buffer-point ,buf) (max min* (min p max*)))))))))

(cl:defvar tab-width 8)

(cl:defun current-column ()
  "Bring-up subset of ELisp `current-column'."
  (let* ((txt (elisp-buffer-text *current-buffer*))
         ;; ELisp point is 1-based, and points between characters.
         (idx (1- (point)))
         (line-start (or (cl:position #\Newline txt :end idx :from-end t) -1))
         (col 0))
    (loop for i from (1+ line-start) below idx do
      (let ((ch (char txt i)))
        (if (char= ch #\Tab)
            (incf col (- tab-width (mod col tab-width)))
            (incf col 1))))
    col))

(cl:defun line-number-at-pos (&optional pos absolute)
  "Bring-up subset of ELisp `line-number-at-pos'.

If ABSOLUTE is non-nil, count lines from the start of the buffer.  Otherwise,
count from `point-min' (respects narrowing)."
  (let* ((p (if pos (%pos pos) (point)))
         (start (if absolute 1 (point-min)))
         (p* (max start (min p (point-max))))
         (txt (elisp-buffer-text *current-buffer*))
         (start-idx (max 0 (1- start)))
         (end-idx (max start-idx (min (length txt) (1- p*)))))
    (1+ (count #\Newline txt :start start-idx :end end-idx))))

(cl:defun bounds-of-thing-at-point (&rest _args)
  "Bring-up stub for ELisp `bounds-of-thing-at-point'."
  (declare (cl:ignore _args))
  nil)

(cl:defun thing-at-point (&rest _args)
  "Bring-up stub for ELisp `thing-at-point'."
  (declare (cl:ignore _args))
  nil)

(cl:defun move-to-column (column &optional force)
  "Bring-up subset of ELisp `move-to-column'."
  (declare (cl:ignore force))
  (let ((col (max 0 (or column 0)))
        (cur 0))
    (beginning-of-line)
    (loop while (and (< cur col) (not (eolp))) do
      (let ((c (char-after)))
        (cond
         ((null c) (return))
         ((= c (char-code #\Tab))
          (incf cur (- tab-width (mod cur tab-width))))
         (t
          (incf cur 1))))
      (forward-char 1)))
  (current-column))

(cl:defun string-width (string &optional _from _to _buffer)
  "Bring-up subset of ELisp `string-width'."
  (declare (cl:ignore _from _to _buffer))
  (unless (stringp string)
    (error "ELISP:STRING-WIDTH expects a string, got: ~S" string))
  (length (%elisp-string->cl-string string)))

(cl:defun line-number-display-width (&optional _mode)
  "Bring-up stub for the C primitive `line-number-display-width' (TTY)."
  (declare (cl:ignore _mode))
  0)

(cl:defun window-width (&optional window pixelwise)
  "Bring-up subset of ELisp `window-width' (single-window, TTY)."
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-WIDTH expected live window, got: ~S" w))
    (if pixelwise
        (window-pixel-width w)
      (window-total-width w))))

(cl:defun window-height (&optional window pixelwise)
  "Bring-up subset of ELisp `window-height' (single-window, TTY)."
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-HEIGHT expected live window, got: ~S" w))
    (if pixelwise
        (window-pixel-height w)
      (window-total-height w))))

(cl:defun window-total-height (&optional window round)
  "Bring-up subset of the C primitive `window-total-height' (single-window, TTY)."
  (declare (cl:ignore round))
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-TOTAL-HEIGHT expected live window, got: ~S" w))
    (handler-case
        (multiple-value-bind (rows _cols) (clemacs::tty-winsize)
          (declare (cl:ignore _cols))
          (if (and (integerp rows) (> rows 0)) rows 24))
      (cl:error () 24))))

(cl:defun window-total-width (&optional window round)
  "Bring-up subset of the C primitive `window-total-width' (single-window, TTY)."
  (declare (cl:ignore round))
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-TOTAL-WIDTH expected live window, got: ~S" w))
    (handler-case
        (multiple-value-bind (_rows cols) (clemacs::tty-winsize)
          (declare (cl:ignore _rows))
          (if (and (integerp cols) (> cols 0)) cols 80))
      (cl:error () 80))))

(cl:defun recenter (&optional _arg)
  "Bring-up stub for ELisp `recenter'."
  (declare (cl:ignore _arg))
  nil)

(cl:defun forward-comment (count &optional limit)
  "Bring-up subset of ELisp `forward-comment'.

This is currently just enough for pp.el: skip whitespace and `;` line comments."
  (declare (cl:ignore count))
  (let* ((txt (elisp-buffer-text *current-buffer*))
         (stop (or limit (point-max)))
         (pos (point)))
    (labels ((at (p)
               (and (<= (point-min) p) (< p stop)
                    (char txt (1- p)))))
      (loop while (< pos stop) do
        (let ((ch (at pos)))
          (cond
           ((null ch) (return))
           ((or (char= ch #\Space)
                (char= ch #\Tab)
                (char= ch #\Newline)
                (char= ch #\Return)
                (char= ch #\Page))
            (incf pos))
           ((char= ch #\;)
            (loop while (and (< pos stop)
                             (let ((c (at pos)))
                               (and c (not (char= c #\Newline)))))
                  do (incf pos))
           (when (and (< pos stop) (char= (at pos) #\Newline))
              (incf pos)))
           (t (return))))))
    (goto-char pos)
    nil))

(cl:defun parse-partial-sexp (from to &optional targetdepth stopbefore oldstate commentstop)
  "Bring-up subset of the C primitive `parse-partial-sexp'.

This implementation is intentionally minimal and syntax-table-ignorant: it
tracks parentheses, strings, and `;` line comments for Emacs Lisp-like syntax.

It also moves point to where the scan stopped (like the C primitive)."
  (declare (cl:ignore stopbefore))
  (unless (and (integerp from) (integerp to))
    (error "ELISP:PARSE-PARTIAL-SEXP expected integer region, got: ~S..~S" from to))
  (let* ((txt (elisp-buffer-text *current-buffer*))
         (limit (max 1 (min to (point-max))))
         (pos (max 1 (min from limit)))
         (depth 0)
         (min-depth 0)
         (in-string-delim nil)
         (in-comment nil)
         (after-quote nil)
         (comstr-start nil)
         ;; Internal stack representation: innermost-first for O(1) push/pop.
         (paren-stack-r nil))
    (when (consp oldstate)
      (setf depth (or (nth 0 oldstate) 0)
            min-depth (or (nth 6 oldstate) depth)
            in-string-delim (let ((d (nth 3 oldstate)))
                              (cond
                               ((null d) nil)
                               ((eq d t) 34)
                               ((integerp d) d)
                               (t 34)))
            in-comment (and (nth 4 oldstate) t)
            after-quote (and (nth 5 oldstate) t)
            comstr-start (nth 8 oldstate)
            paren-stack-r (reverse (or (nth 9 oldstate) nil))))
    (labels ((at (p)
               (and (<= 1 p) (< p (point-max))
                    (char txt (1- p))))
             (push-paren (p)
               (push p paren-stack-r)
               (incf depth))
             (pop-paren ()
               (when (> depth 0)
                 (decf depth))
               (when paren-stack-r
                 (pop paren-stack-r))))
      (loop while (< pos limit) do
        (let ((ch (at pos)))
          (when (null ch)
            (return))
          (cond
           ((and in-comment (char= ch #\Newline))
            (setf in-comment nil comstr-start nil after-quote nil)
            (incf pos))
           (in-comment
            (incf pos))
           (in-string-delim
            (cond
             ((char= ch #\\)
              (incf pos (if (< (1+ pos) limit) 2 1)))
             ((and (integerp in-string-delim)
                   (= (char-code ch) in-string-delim))
              (setf in-string-delim nil comstr-start nil after-quote nil)
              (incf pos))
             (t
              (incf pos))))
           (t
            (setf after-quote nil)
            (cond
             ((char= ch #\;)
              ;; In Emacs Lisp, semicolon starts a line comment.
              (setf in-comment t comstr-start pos)
              (incf pos)
              (when commentstop
                (return)))
             ((char= ch #\")
              (setf in-string-delim 34 comstr-start pos)
              (incf pos))
             ((char= ch #\()
              (push-paren pos)
              (incf pos))
             ((char= ch #\))
              (pop-paren)
              (setf min-depth (min min-depth depth))
              (incf pos))
             (t
              (incf pos))))))
        (when (and (integerp targetdepth)
                   (= depth targetdepth))
          (return))))
      ;; Like the C primitive, update point to where we stopped scanning.
      (goto-char pos)
      (let* ((stack (reverse paren-stack-r))
             (prevlevelstart (car (last stack))))
        (list depth
              prevlevelstart
              nil
              in-string-delim
              (and in-comment t)
              (and after-quote t)
              min-depth
              nil
              comstr-start
              stack
              nil))))

(cl:defun goto-char (pos)
  "Bring-up subset of ELisp `goto-char'.

Emacs clamps positions outside the buffer to the nearest valid position."
  (let* ((p (%pos pos))
         (p* (max (point-min) (min p (point-max)))))
    (setf (elisp-buffer-point *current-buffer*) p*)
    p*))

(cl:defun forward-char (&optional n)
  "Bring-up subset of ELisp `forward-char'."
  (let* ((n (or n 1))
         (target (+ (point) n)))
    (unless (integerp n)
      (error "ELISP:FORWARD-CHAR bad arg: ~S" n))
    (cond
     ((< target (point-min))
      (goto-char (point-min))
      (signal 'beginning-of-buffer nil))
     ((> target (point-max))
      (goto-char (point-max))
      (signal 'end-of-buffer nil))
     (t
      (goto-char target)
      nil))))

(cl:defun forward-line (&optional n)
  "Bring-up subset of ELisp `forward-line'."
  (let* ((n (or n 1))
         (txt (elisp-buffer-text *current-buffer*))
         (moved 0))
    (unless (integerp n)
      (error "ELISP:FORWARD-LINE bad arg: ~S" n))
    (labels ((next-line-start (p)
               (let* ((idx (1- p))
                      (nl (cl:position #\Newline txt :start idx)))
                 (if nl
                     (+ nl 2)
                     (point-max))))
             (prev-line-start (p)
               (let* ((idx (1- p))
                      (nl (cl:position #\Newline txt :end idx :from-end t)))
                 (if nl
                     (let* ((nl2 (cl:position #\Newline txt :end nl :from-end t)))
                       (if nl2 (+ nl2 2) (point-min)))
                     (point-min)))))
      (cond
       ((> n 0)
        (dotimes (_ n)
          (let ((p (point)))
            (when (>= p (point-max))
              (return))
            (goto-char (next-line-start p))
            (incf moved))))
       ((< n 0)
        (dotimes (_ (- n))
          (let ((p (point)))
            (when (<= p (point-min))
              (return))
            (goto-char (prev-line-start p))
            (incf moved))))))
    ;; Emacs returns 0 when it moved N lines, otherwise the number of
    ;; lines remaining.  We approximate with (N - MOVED) for positive N.
    (cond
     ((>= n 0) (- n moved))
     (t (+ n moved)))))

(cl:defun vertical-motion (count &optional _window _curcol _end-of-window)
  "Bring-up subset of the C primitive `vertical-motion'."
  (declare (cl:ignore _window _curcol _end-of-window))
  (let ((n (prefix-numeric-value (or count 0))))
    (cond
     ((= n 0)
      (beginning-of-line)
      0)
     (t
      (let ((ret (forward-line n)))
        (if (>= n 0)
            (- n ret)
            (- ret n)))))))

(cl:defun line-end-position (&optional n)
  "Bring-up subset of ELisp `line-end-position'."
  (let ((n (or n 1)))
    (unless (and (integerp n) (> n 0))
      (error "ELISP:LINE-END-POSITION bad arg: ~S" n))
    (save-excursion
      (when (> n 1)
        (forward-line (1- n)))
      (let* ((txt (elisp-buffer-text *current-buffer*))
             (idx (1- (point)))
             (nl (cl:position #\Newline txt :start idx)))
        (if nl
            (1+ nl)
            (point-max))))))

(cl:defun line-beginning-position (&optional n)
  "Bring-up subset of ELisp `line-beginning-position'."
  (let ((n (or n 1)))
    (unless (and (integerp n) (> n 0))
      (error "ELISP:LINE-BEGINNING-POSITION bad arg: ~S" n))
    (save-excursion
      (when (> n 1)
        (forward-line (1- n)))
      (let* ((txt (elisp-buffer-text *current-buffer*))
             (idx (1- (point)))
             (nl (cl:position #\Newline txt :end idx :from-end t)))
        (if nl
            (+ nl 2)
            (point-min))))))

(cl:defun pos-bol ()
  "Bring-up subset of the C primitive `pos-bol'."
  (line-beginning-position))

(cl:defun beginning-of-line (&optional n)
  "Bring-up subset of ELisp `beginning-of-line'."
  (let ((n (or n 1)))
    (unless (integerp n)
      (error "ELISP:BEGINNING-OF-LINE bad arg: ~S" n))
    (when (/= n 1)
      (forward-line (1- n)))
    (goto-char (line-beginning-position))
    nil))

(cl:defun end-of-line (&optional n)
  "Bring-up subset of ELisp `end-of-line'."
  (let ((n (or n 1)))
    (unless (integerp n)
      (error "ELISP:END-OF-LINE bad arg: ~S" n))
    (when (/= n 1)
      (forward-line (1- n)))
    (goto-char (line-end-position))
    nil))

(cl:defun backward-char (&optional n)
  "Bring-up subset of ELisp `backward-char'."
  (let ((n (or n 1)))
    (unless (integerp n)
      (error "ELISP:BACKWARD-CHAR bad arg: ~S" n))
    (forward-char (- n))))

(cl:defun %word-char-p (code)
  (and (integerp code)
       (let ((ch (code-char code)))
         (and ch (or (alphanumericp ch) (char= ch #\_))))))

(cl:defun forward-word (&optional n)
  "Bring-up subset of the C primitive `forward-word'."
  (let ((n (or n 1)))
    (unless (integerp n)
      (error "ELISP:FORWARD-WORD bad arg: ~S" n))
    (cond
     ((= n 0) nil)
     ((> n 0)
      (dotimes (_ n)
        (loop while (and (not (eobp)) (not (%word-char-p (char-after))))
              do (forward-char 1))
        (loop while (and (not (eobp)) (%word-char-p (char-after)))
              do (forward-char 1))))
     (t
      (dotimes (_ (- n))
        (loop while (and (not (bobp)) (not (%word-char-p (char-before))))
              do (backward-char 1))
        (loop while (and (not (bobp)) (%word-char-p (char-before)))
              do (backward-char 1))))))
  nil)

(cl:defun backward-word (&optional n)
  "Bring-up subset of the C primitive `backward-word'."
  (forward-word (- (or n 1))))

(cl:defun count-words--format (str start end)
  "Bring-up subset of `count-words--format'.

Upstream `lisp/simple.el' calls this helper before defining it later in the
file, which causes forward-reference warnings under SBCL.  Provide a minimal
implementation here; the upstream definition will override it once loaded."
  (let* ((label (if (stringp str) str (prin1-to-string str)))
         (a (or (ignore-errors (%pos start)) 0))
         (b (or (ignore-errors (%pos end)) 0))
         (chars (abs (- b a))))
    (format "%s has %d character%s" label chars (if (= chars 1) "" "s"))))

(cl:defun back-to-indentation ()
  "Bring-up subset of ELisp `back-to-indentation'."
  (beginning-of-line)
  (skip-chars-forward " \t")
  nil)

(cl:defun current-indentation ()
  "Bring-up subset of ELisp `current-indentation'."
  (save-excursion
    (back-to-indentation)
    (current-column)))

(cl:defun current-left-margin (&optional _pos _window)
  "Bring-up stub for ELisp `current-left-margin'."
  (declare (cl:ignore _pos _window))
  0)

(cl:defun move-to-left-margin (&optional n _force)
  "Bring-up stub for ELisp `move-to-left-margin'."
  (declare (cl:ignore _force))
  (when (and n (/= n 1))
    (forward-line (1- n)))
  (back-to-indentation)
  nil)

(cl:defun delete-horizontal-space (&optional backward-only)
  "Bring-up subset of ELisp `delete-horizontal-space'."
  (let ((start (point))
        (end (point)))
    (loop while (let ((c (char-before start)))
                  (and c (or (= c (char-code #\Space))
                             (= c (char-code #\Tab)))))
          do (decf start))
    (unless backward-only
      (loop while (let ((c (char-after end)))
                    (and c (or (= c (char-code #\Space))
                               (= c (char-code #\Tab)))))
            do (incf end)))
    (when (< start end)
      (delete-region start end))
    nil))

(cl:defun indent-to (column &optional minimum)
  "Bring-up subset of ELisp `indent-to' (spaces only)."
  (unless (and (integerp column) (>= column 0))
    (error "ELISP:INDENT-TO bad column: ~S" column))
  (when minimum
    (unless (and (integerp minimum) (>= minimum 0))
      (error "ELISP:INDENT-TO bad minimum: ~S" minimum)))
  (let* ((cur (current-column))
         (need (max 0 (- column cur)))
         (need (if minimum (max minimum need) need)))
    (when (> need 0)
      (insert (cl:make-string need :initial-element #\Space)))
    (current-column)))

(cl:defun indent-to-left-margin ()
  "Bring-up subset of ELisp `indent-to-left-margin'."
  (indent-to 0))

(cl:defun use-region-p ()
  "Bring-up subset of ELisp `use-region-p'."
  (and (region-active-p) t))

(cl:defun region-beginning ()
  "Bring-up subset of ELisp `region-beginning'."
  (let ((mpos (and (markerp (mark-marker))
                   (marker-position (mark-marker)))))
    (unless (integerp mpos)
      (error "ELISP:REGION-BEGINNING no mark"))
    (min (point) mpos)))

(cl:defun region-end ()
  "Bring-up subset of ELisp `region-end'."
  (let ((mpos (and (markerp (mark-marker))
                   (marker-position (mark-marker)))))
    (unless (integerp mpos)
      (error "ELISP:REGION-END no mark"))
    (max (point) mpos)))

(cl:defun mark-marker ()
  "Bring-up subset of ELisp `mark-marker'."
  (let ((v (and (boundp 'mark-marker) (symbol-value 'mark-marker))))
    (unless (markerp v)
      (set 'mark-marker (make-marker))
      (setf v (symbol-value 'mark-marker)))
    v))

(cl:defun mark (&optional force)
  "Bring-up subset of the C primitive `mark'."
  (let* ((m (mark-marker))
         (p (and (markerp m) (marker-position m))))
    (cond
     ((integerp p) p)
     (force (error "Mark is not set"))
     (t nil))))

(cl:defun region-active-p ()
  "Bring-up subset of ELisp `region-active-p'."
  (and (boundp 'transient-mark-mode)
       (symbol-value 'transient-mark-mode)
       (boundp 'mark-active)
       (symbol-value 'mark-active)
       (let ((m (mark-marker)))
         (and (markerp m) (integerp (marker-position m))))
       t))

(cl:defun push-mark (&optional location nomsg activate)
  "Bring-up subset of ELisp `push-mark'."
  (let* ((m (mark-marker))
         (buf (current-buffer))
         (loc (or location (point))))
    ;; Push old mark onto the mark ring if it was set.
    (let ((oldpos (and (markerp m) (marker-position m))))
      (when (integerp oldpos)
        (set 'mark-ring
             (cons (copy-marker m t)
                   (and (boundp 'mark-ring)
                        (symbol-value 'mark-ring))))))
    (set-marker m loc buf)
    (set 'mark-active
         (cond
          ((and (boundp 'transient-mark-mode) (symbol-value 'transient-mark-mode))
           (and activate t))
          (t t)))
    (unless nomsg
      (message "Mark set"))
    m))

(cl:defun point-max-marker ()
  (let ((m (make-elisp-marker :buffer *current-buffer*
                              :position (point-max)
                              :edit-index (%buffer-edit-index *current-buffer*))))
    (%buffer-register-marker *current-buffer* m)
    m))

(cl:defun set-marker (marker position &optional buffer)
  (unless (elisp-marker-p marker)
    (error "ELISP:SET-MARKER expected marker, got: ~S" marker))
  (let ((old (elisp-marker-buffer marker)))
    (cond
     ((null position)
      (when (elisp-buffer-p old)
        (%buffer-unregister-marker old marker)))
     (t
      (let ((new (or buffer *current-buffer*)))
        (when (and (elisp-buffer-p old) (not (eq old new)))
          (%buffer-unregister-marker old marker))))))
  (cond
   ((null position)
    (setf (elisp-marker-buffer marker) nil
          (elisp-marker-position marker) nil
          (elisp-marker-edit-index marker) 0))
   (t
    (unless (and (integerp position) (plusp position))
      (error "ELISP:SET-MARKER bad position: ~S" position))
    (let ((buf (or buffer *current-buffer*)))
      (setf (elisp-marker-buffer marker) buf
            (elisp-marker-position marker) (max 1
                                                (min position (1+ (length (elisp-buffer-text buf)))))
            (elisp-marker-edit-index marker) (%buffer-edit-index buf))
      (%buffer-register-marker buf marker))))
  marker)

(defstruct elisp-overlay
  (start-marker (make-elisp-marker))
  (end-marker (make-elisp-marker))
  (buffer nil)
  (plist nil))

(cl:defun overlayp (x)
  (elisp-overlay-p x))

(cl:defun overlay-buffer (overlay)
  (unless (elisp-overlay-p overlay)
    (error "ELISP:OVERLAY-BUFFER expected overlay, got: ~S" overlay))
  (elisp-overlay-buffer overlay))

(cl:defun overlay-start (overlay)
  (unless (elisp-overlay-p overlay)
    (error "ELISP:OVERLAY-START expected overlay, got: ~S" overlay))
  (let ((m (elisp-overlay-start-marker overlay)))
    (and (elisp-marker-p m) (marker-position m))))

(cl:defun overlay-end (overlay)
  (unless (elisp-overlay-p overlay)
    (error "ELISP:OVERLAY-END expected overlay, got: ~S" overlay))
  (let ((m (elisp-overlay-end-marker overlay)))
    (and (elisp-marker-p m) (marker-position m))))

(cl:defun overlay-properties (overlay)
  (unless (elisp-overlay-p overlay)
    (error "ELISP:OVERLAY-PROPERTIES expected overlay, got: ~S" overlay))
  (elisp-overlay-plist overlay))

(cl:defun overlay-put (overlay prop value)
  (unless (elisp-overlay-p overlay)
    (error "ELISP:OVERLAY-PUT expected overlay, got: ~S" overlay))
  (setf (elisp-overlay-plist overlay)
        (plist-put (elisp-overlay-plist overlay) prop value))
  value)

(cl:defun overlay-get (overlay prop)
  (unless (elisp-overlay-p overlay)
    (error "ELISP:OVERLAY-GET expected overlay, got: ~S" overlay))
  (plist-get (elisp-overlay-plist overlay) prop))

(cl:defun overlay-recenter (&rest _args)
  "Bring-up stub for ELisp `overlay-recenter'."
  (declare (cl:ignore _args))
  nil)

(cl:defun make-overlay (start end &optional buffer front-advance rear-advance)
  "Bring-up subset of ELisp `make-overlay'."
  (let* ((buf (or buffer *current-buffer*))
         (a (%pos start))
         (b (%pos end))
         (min (min a b))
         (max (max a b))
         (m1 (make-marker))
         (m2 (make-marker)))
    (unless (elisp-buffer-p buf)
      (error "ELISP:MAKE-OVERLAY expected buffer, got: ~S" buf))
    (set-marker m1 min buf)
    (setf (elisp-marker-insertion-type m1) (and front-advance t))
    (set-marker m2 max buf)
    (setf (elisp-marker-insertion-type m2) (and rear-advance t))
    (let ((ov (make-elisp-overlay :start-marker m1 :end-marker m2 :buffer buf :plist nil)))
      (setf (elisp-buffer-overlays buf) (cons ov (elisp-buffer-overlays buf)))
      ov)))

(cl:defun delete-overlay (overlay)
  "Bring-up subset of ELisp `delete-overlay'."
  (unless (elisp-overlay-p overlay)
    (error "ELISP:DELETE-OVERLAY expected overlay, got: ~S" overlay))
  (let ((buf (elisp-overlay-buffer overlay)))
    (when (elisp-buffer-p buf)
      (setf (elisp-buffer-overlays buf) (remove overlay (elisp-buffer-overlays buf) :test #'eq))))
  (setf (elisp-overlay-buffer overlay) nil)
  (let ((m (elisp-overlay-start-marker overlay)))
    (when (elisp-marker-p m) (set-marker m nil)))
  (let ((m (elisp-overlay-end-marker overlay)))
    (when (elisp-marker-p m) (set-marker m nil)))
  nil)

(cl:defun move-overlay (overlay start end &optional buffer)
  "Bring-up subset of ELisp `move-overlay'."
  (unless (elisp-overlay-p overlay)
    (error "ELISP:MOVE-OVERLAY expected overlay, got: ~S" overlay))
  (let* ((buf (or buffer (elisp-overlay-buffer overlay)))
         (old (elisp-overlay-buffer overlay))
         (a (%pos start))
         (b (%pos end))
         (min (min a b))
         (max (max a b)))
    (unless (elisp-buffer-p buf)
      (error "ELISP:MOVE-OVERLAY expected buffer, got: ~S" buf))
    (when (and (elisp-buffer-p old) (not (eq old buf)))
      (setf (elisp-buffer-overlays old) (remove overlay (elisp-buffer-overlays old) :test #'eq))
      (setf (elisp-buffer-overlays buf) (cons overlay (elisp-buffer-overlays buf))))
    (setf (elisp-overlay-buffer overlay) buf)
    (let ((m1 (elisp-overlay-start-marker overlay))
          (m2 (elisp-overlay-end-marker overlay)))
      (set-marker m1 min buf)
      (set-marker m2 max buf))
    overlay))

(cl:defun get-char-property (pos prop &optional object)
  "Bring-up subset of the C primitive `get-char-property'.

This checks overlays first (when OBJECT is a buffer), then falls back to
`get-text-property'."
  (cond
   ((or (null object) (bufferp object))
    (let* ((buf (or object (current-buffer)))
           (p (%pos pos)))
      (dolist (ov (and (elisp-buffer-p buf) (elisp-buffer-overlays buf)))
        (when (and (elisp-overlay-p ov)
                   (eq (elisp-overlay-buffer ov) buf))
          (let ((s (overlay-start ov))
                (e (overlay-end ov)))
            (when (and (integerp s) (integerp e) (<= s p) (< p e))
              (let ((v (overlay-get ov prop)))
                (when v (return-from get-char-property v)))))))
      (get-text-property pos prop buf)))
   (t
    (get-text-property pos prop object))))

(cl:defun %pos (x)
  (etypecase x
    (integer x)
    (elisp-marker (or (marker-position x) (error "Marker has no position")))))

(cl:defun %num (x)
  (typecase x
    (elisp-marker (%pos x))
    (integer x)
    (real x)
    (t (signal 'wrong-type-argument (list 'number-or-marker-p x)))))

(cl:defun prefix-numeric-value (raw)
  "Bring-up subset of ELisp `prefix-numeric-value'."
  (cond
   ((null raw) 1)
   ((eq raw t) 1)
   ((integerp raw) raw)
   ((eq raw '-) -1)
   ((consp raw)
    (let ((x (car raw)))
      (cond
       ((integerp x) x)
       ((eq x '-) -1)
       (t (error "ELISP:PREFIX-NUMERIC-VALUE bad raw prefix: ~S" raw)))))
   (t (error "ELISP:PREFIX-NUMERIC-VALUE bad raw prefix: ~S" raw))))

(cl:defun 1+ (x)
  "Bring-up subset of ELisp `1+'."
  (+ x 1))

(cl:defun 1- (x)
  "Bring-up subset of ELisp `1-'."
  (- x 1))

(cl:defun < (a b &rest more)
  "Bring-up subset of ELisp `<'."
  (let ((prev (%num a))
        (cur (%num b)))
    (unless (cl:< prev cur)
      (return-from < nil))
    (dolist (x more t)
      (setf prev cur
            cur (%num x))
      (unless (cl:< prev cur)
        (return-from < nil)))))

(cl:defun <= (a b &rest more)
  "Bring-up subset of ELisp `<='."
  (let ((prev (%num a))
        (cur (%num b)))
    (unless (cl:<= prev cur)
      (return-from <= nil))
    (dolist (x more t)
      (setf prev cur
            cur (%num x))
      (unless (cl:<= prev cur)
        (return-from <= nil)))))

(cl:defun > (a b &rest more)
  "Bring-up subset of ELisp `>'."
  (let ((prev (%num a))
        (cur (%num b)))
    (unless (cl:> prev cur)
      (return-from > nil))
    (dolist (x more t)
      (setf prev cur
            cur (%num x))
      (unless (cl:> prev cur)
        (return-from > nil)))))

(cl:defun >= (a b &rest more)
  "Bring-up subset of ELisp `>='."
  (let ((prev (%num a))
        (cur (%num b)))
    (unless (cl:>= prev cur)
      (return-from >= nil))
    (dolist (x more t)
      (setf prev cur
            cur (%num x))
      (unless (cl:>= prev cur)
        (return-from >= nil)))))

(cl:defun = (a b &rest more)
  "Bring-up subset of ELisp `='."
  (let ((prev (%num a))
        (cur (%num b)))
    (unless (cl:= prev cur)
      (return-from = nil))
    (dolist (x more t)
      (setf prev cur
            cur (%num x))
      (unless (cl:= prev cur)
        (return-from = nil)))))

(cl:defun buffer-substring (start end)
  (let* ((s (%pos start))
         (e (%pos end))
         (txt (elisp-buffer-text *current-buffer*)))
    (when (> s e)
      (error "ELISP:BUFFER-SUBSTRING start > end: ~S ~S" start end))
    (subseq txt (1- s) (1- e))))

(cl:defun buffer-substring-no-properties (start end)
  "Bring-up subset of ELisp `buffer-substring-no-properties'."
  (buffer-substring start end))

(cl:defun insert-buffer-substring (buffer &optional start end)
  "Bring-up subset of ELisp `insert-buffer-substring'."
  (let ((src (cond
              ((bufferp buffer) buffer)
              ((stringp buffer) (get-buffer buffer))
              (t (error "ELISP:INSERT-BUFFER-SUBSTRING bad buffer: ~S" buffer)))))
    (unless (bufferp src)
      (error "ELISP:INSERT-BUFFER-SUBSTRING no such buffer: ~S" buffer))
    (let ((chunk
            (with-current-buffer src
              (buffer-substring (or start (point-min)) (or end (point-max))))))
      (insert chunk)
      nil)))

(cl:defun delete-region (start end)
  (let* ((s (%pos start))
         (e (%pos end))
         (txt (elisp-buffer-text *current-buffer*)))
    (when (> s e)
      (error "ELISP:DELETE-REGION start > end: ~S ~S" start end))
    (let ((intervals (%buffer-text-properties *current-buffer*)))
      (when intervals
        (let ((new (%buffer-intervals-delete intervals s e)))
          (if new
              (%set-buffer-text-properties *current-buffer* new)
              (%clear-buffer-text-properties *current-buffer*)))))
    (%buffer-record-delete *current-buffer* s e)
    (setf (elisp-buffer-text *current-buffer*)
          (concatenate 'cl:string (subseq txt 0 (1- s)) (subseq txt (1- e))))
    (when (> (point) (point-max))
      (goto-char (point-max)))
    nil))

(cl:defun call-process (program &optional infile destination _display &rest args)
  "Bring-up subset of the C primitive `call-process'."
  (declare (cl:ignore _display))
  (unless (stringp program)
    (error "ELISP:CALL-PROCESS expected string PROGRAM, got: ~S" program))
  (labels ((arg->string (a)
             (cond
              ((null a) nil)
              ((stringp a) (%elisp-string->cl-string a))
              ((symbolp a) (symbol-name a))
              (t (prin1-to-string a))))
           (resolve-dest (d)
             (cond
              ((null d) nil)
              ((or (eq d t) (and (integerp d) (zerop d))) (current-buffer))
              ((stringp d) (get-buffer-create d))
              ((bufferp d) d)
              (t (error "ELISP:CALL-PROCESS unsupported DESTINATION: ~S" d))))
           (split-destination (d)
             ;; Emacs accepts (OUT . ERR) and (OUT ERR).  We treat both.
             (cond
              ((consp d)
               (cond
                ((and (consp (cdr d)) (null (cddr d)))
                 (cl:values (car d) (cadr d)))
                (t (cl:values (car d) (cdr d)))))
              (t
               (cl:values d d)))))
    (let* ((cmd (cons (%elisp-string->cl-string program)
                      (remove nil (mapcar #'arg->string args))))
           (input-kind
             (cond
              ((or (null infile) (and (integerp infile) (zerop infile))) :eof)
              ((eq infile t) :buffer)
              ((stringp infile) :file)
              (t (error "ELISP:CALL-PROCESS unsupported INFILE: ~S" infile)))))
      (multiple-value-bind (outdest errdest) (split-destination destination)
        (let ((outbuf (resolve-dest outdest))
              (errbuf (resolve-dest errdest)))
          (flet ((insert-into (buf s)
                   (when (and buf s (> (length s) 0))
                     (with-current-buffer buf
                       (insert s)))))
            (multiple-value-bind (out err code)
                (ecase input-kind
                  (:eof
                   (uiop:run-program cmd
                                     :input (make-string-input-stream "")
                                     :output :string
                                     :error-output :string
                                     :ignore-error-status t))
                  (:buffer
                   (let ((input (%elisp-string->cl-string
                                 (buffer-substring-no-properties (point-min) (point-max)))))
                     (uiop:run-program cmd
                                       :input (make-string-input-stream input)
                                       :output :string
                                       :error-output :string
                                       :ignore-error-status t)))
                  (:file
                   (with-open-file (in (%elisp-string->cl-string infile)
                                       :direction :input
                                       :external-format :utf-8)
                     (uiop:run-program cmd
                                       :input in
                                       :output :string
                                       :error-output :string
                                       :ignore-error-status t))))
              (insert-into outbuf out)
              ;; If stderr is destined for the same buffer, avoid double insert.
              (unless (and outbuf errbuf (eq outbuf errbuf))
                (insert-into errbuf err))
              code)))))))

(cl:defun call-process-region (start end program &optional delete destination _display &rest args)
  "Bring-up subset of the C primitive `call-process-region'."
  (declare (cl:ignore _display))
  (unless (stringp program)
    (error "ELISP:CALL-PROCESS-REGION expected string PROGRAM, got: ~S" program))
  (let* ((s (%pos start))
         (e (%pos end))
         (input (%elisp-string->cl-string (buffer-substring-no-properties s e)))
         (cmd (cons (%elisp-string->cl-string program)
                    (mapcar (lambda (a)
                              (cond
                               ((stringp a) (%elisp-string->cl-string a))
                               ((symbolp a) (symbol-name a))
                               (t (prin1-to-string a))))
                            args))))
    (when delete
      (delete-region s e))
    (multiple-value-bind (out _err code)
        (uiop:run-program cmd
                          :input (make-string-input-stream input)
                          :output :string
                          :error-output :string
                          :ignore-error-status t)
      (declare (cl:ignore _err))
      (let ((dest
              (cond
               ((null destination) nil)
               ((or (eq destination t) (and (integerp destination) (zerop destination)))
                (current-buffer))
               ((stringp destination) (get-buffer-create destination))
               ((bufferp destination) destination)
               (t (error "ELISP:CALL-PROCESS-REGION unsupported DESTINATION: ~S"
                         destination)))))
        (when dest
          (with-current-buffer dest
            (goto-char (point-max))
            (insert out)))
        code))))

(cl:defun delete-char (n &optional _killflag)
  "Bring-up subset of ELisp `delete-char'."
  (declare (cl:ignore _killflag))
  (unless (integerp n)
    (error "ELISP:DELETE-CHAR expects integer N, got: ~S" n))
  (cond
   ((zerop n) nil)
   ((plusp n)
    (delete-region (point) (min (point-max) (+ (point) n))))
   (t
    (delete-region (max (point-min) (+ (point) n)) (point))))
  nil)

(cl:defun %set-buffer-match-data (mstart mend reg-starts reg-ends &key (base 0))
  (let ((md nil))
    (push (and (integerp mstart) (<= 0 mstart) (+ base mstart 1)) md)
    (push (and (integerp mend) (<= 0 mend) (+ base mend 1)) md)
    (when reg-starts
      (loop for rs across reg-starts
            for re across reg-ends do
              (push (and (integerp rs) (<= 0 rs) (+ base rs 1)) md)
              (push (and (integerp re) (<= 0 re) (+ base re 1)) md)))
    (setf *match-data* (nreverse md)
          *match-source-string* nil)
    md))

(cl:defun looking-at (regexp)
  "Bring-up subset of ELisp `looking-at'."
  (unless (stringp regexp)
    (error "ELISP:LOOKING-AT expects a string, got: ~S" regexp))
  (let* ((s (elisp-buffer-text *current-buffer*))
         (start (1- (point))))
    ;; Important: `looking-at' must only try a match at point (no forward search),
    ;; otherwise it can become pathologically slow on large buffers (pp.el relies
    ;; on this being cheap).  Avoid SUBSEQ here; use an anchored scanner and set
    ;; :REAL-START-POS to the match start so \\A behaves like "at point".
    (multiple-value-bind (mstart mend reg-starts reg-ends)
        (cl-ppcre:scan (%string-match-anchored-scanner regexp case-fold-search)
                       s
                       :start start
                       :end (length s)
                       :real-start-pos start)
      (if (or (null mstart) (/= mstart start))
          (progn
            (setf *match-data* nil *match-source-string* nil)
            nil)
          (progn
            (%set-buffer-match-data mstart mend reg-starts reg-ends)
            t)))))

(cl:defun looking-back (regexp &optional limit _greedy)
  "Bring-up subset of ELisp `looking-back'."
  (declare (cl:ignore _greedy))
  (unless (stringp regexp)
    (error "ELISP:LOOKING-BACK expects a string, got: ~S" regexp))
  (let* ((s (elisp-buffer-text *current-buffer*))
         (end (1- (point)))
         (lim (max (point-min) (or limit (point-min))))
         (lim-idx (1- lim)))
    (when (< end lim-idx)
      (setf *match-data* nil *match-source-string* nil)
      (return-from looking-back nil))
    (let* ((sub (subseq s lim-idx end))
           (scanner (%string-match-scanner regexp case-fold-search))
           (best nil)
           (best-reg-starts nil)
           (best-reg-ends nil))
      (cl-ppcre:do-scans (ms me rs re scanner sub)
        (when (= me (length sub))
          (setf best ms best-reg-starts rs best-reg-ends re)))
      (if (null best)
          (progn
            (setf *match-data* nil *match-source-string* nil)
            nil)
          (progn
            (%set-buffer-match-data best (length sub) best-reg-starts best-reg-ends :base lim-idx)
            t)))))

(cl:defun re-search-forward (regexp &optional bound noerror count)
  "Bring-up subset of ELisp `re-search-forward'."
  (unless (stringp regexp)
    (error "ELISP:RE-SEARCH-FORWARD expects a string, got: ~S" regexp))
  (let ((count (or count 1)))
    (unless (and (integerp count) (< 0 count))
      (error "ELISP:RE-SEARCH-FORWARD bad count: ~S" count))
    (loop repeat count
          for s = (elisp-buffer-text *current-buffer*)
          for start = (1- (point))
          for end = (if bound (max 0 (1- (%pos bound))) (length s))
          do
            (multiple-value-bind (mstart mend reg-starts reg-ends)
                (cl-ppcre:scan (%string-match-scanner regexp case-fold-search)
                               s
                               :start start
                               :end end
                               :real-start-pos 0)
              (when (null mstart)
                (setf *match-data* nil *match-source-string* nil)
                (when noerror
                  (return-from re-search-forward nil))
                (error "Search failed: %S" regexp))
              (%set-buffer-match-data mstart mend reg-starts reg-ends)
              (goto-char (1+ mend))))
    (point)))

(cl:defun re-search-backward (regexp &optional bound noerror count)
  "Bring-up subset of ELisp `re-search-backward'."
  (unless (stringp regexp)
    (error "ELISP:RE-SEARCH-BACKWARD expects a string, got: ~S" regexp))
  ;; Fast-path for pp.el's `pp--within-fill-column-p': it calls
  ;;   (re-search-backward "^\\|\n" ...)
  ;; which is just "beginning of line or newline".  Implement this without
  ;; regex to avoid pathological behavior and to more closely match Emacs.
  (let ((re (%elisp-string->cl-string regexp)))
    (when (and (= (length re) 4)
               (char= (char re 0) #\^)
               (char= (char re 1) #\\)
               (char= (char re 2) #\|)
               (char= (char re 3) #\Newline))
      (let* ((count (or count 1)))
        (unless (and (integerp count) (< 0 count))
          (error "ELISP:RE-SEARCH-BACKWARD bad count: ~S" count))
        ;; Only COUNT=1 is used by pp.el; implement just that for now.
        (unless (= count 1)
          (error "ELISP:RE-SEARCH-BACKWARD unsupported COUNT for ^\\\\|\\n fast-path: ~S" count))
        (let* ((txt (elisp-buffer-text *current-buffer*))
               (end (1- (point)))
               (lim (if bound (max (point-min) (%pos bound)) (point-min)))
               (lim-idx (1- lim))
               (nl (cl:position #\Newline txt :end end :from-end t))
               (bol (if nl (+ nl 2) (point-min))))
          (return-from re-search-backward
            (if (< bol lim)
                (progn
                  (setf *match-data* nil *match-source-string* nil)
                  (if noerror nil (error "Search failed: %S" regexp)))
                (progn
                  (setf *match-data* (list bol bol)
                        *match-source-string* nil)
                  (goto-char bol)
                  (point))))))))
  (let ((count (or count 1)))
    (unless (and (integerp count) (< 0 count))
      (error "ELISP:RE-SEARCH-BACKWARD bad count: ~S" count))
    (loop repeat count
          do
            (let* ((s (elisp-buffer-text *current-buffer*))
                   (end (1- (point)))
                   (lim (if bound (max (point-min) (%pos bound)) (point-min)))
                   (lim-idx (1- lim)))
              (when (< end lim-idx)
                (setf *match-data* nil *match-source-string* nil)
                (when noerror
                  (return-from re-search-backward nil))
                (error "Search failed: %S" regexp))
              ;; Avoid `cl-ppcre:do-scans' here: patterns like "^\\|\n" can
              ;; include empty matches (via "^"), and some scan loops can get
              ;; stuck if the match has zero length.  Instead, scan forward
              ;; manually and force progress on empty matches.
              ;;
              ;; Also: do *not* slice SUBSEQ here.  Anchors like `^` should be
              ;; interpreted relative to the whole buffer (Emacs `^` means
              ;; beginning-of-line, which we're approximating with `(?<=\\n)`),
              ;; so we scan the full buffer string with :START/:END bounds.
              (let* ((scanner (%string-match-scanner regexp case-fold-search))
                     (pos lim-idx)
                     (best-ms nil)
                     (best-me nil)
                     (best-rs nil)
                     (best-re nil)
                     (max-end end))
                (loop while (<= pos max-end) do
                  (multiple-value-bind (ms me rs re)
                      (cl-ppcre:scan scanner s :start pos :end max-end :real-start-pos 0)
                    (when (null ms)
                      (return))
                    (setf best-ms ms
                          best-me me
                          best-rs rs
                          best-re re)
                    (setf pos (if (= ms me) (1+ me) me))))
                (when (null best-ms)
                  (setf *match-data* nil *match-source-string* nil)
                  (when noerror
                    (return-from re-search-backward nil))
                  (error "Search failed: %S" regexp))
                (let ((pos (1+ best-ms)))
                  (%set-buffer-match-data best-ms best-me best-rs best-re)
                  (goto-char pos))))))
    (point))

(cl:defun search-forward (string &optional bound noerror count)
  "Bring-up subset of ELisp `search-forward'."
  (unless (stringp string)
    (error "ELISP:SEARCH-FORWARD expects a string, got: ~S" string))
  (let* ((needle (string-to-multibyte string))
         (count* (or count 1)))
    (unless (and (integerp count*) (< 0 count*))
      (error "ELISP:SEARCH-FORWARD bad COUNT: ~S" count))
    (loop repeat count* do
      (let* ((hay (elisp-buffer-text *current-buffer*))
             (start (1- (point)))
             (end (if bound
                      (max start (min (length hay) (1- (%pos bound))))
                      (length hay)))
             (test (if (and (boundp 'case-fold-search) case-fold-search)
                       #'char-equal
                       #'char=))
             (pos (search needle hay :start2 start :end2 end :test test)))
        (when (null pos)
          (setf *match-data* nil *match-source-string* nil)
          (when noerror
            (when (and (eq noerror 'move) bound)
              (goto-char (%pos bound)))
            (return-from search-forward nil))
          (error "Search failed: %S" string))
        (let ((ms pos)
              (me (+ pos (length needle))))
          (%set-buffer-match-data ms me nil nil)
          (goto-char (1+ me)))))
    (point)))

(cl:defun how-many (regexp &optional start end _interactive)
  "Bring-up subset of ELisp `how-many'."
  (declare (cl:ignore _interactive))
  (unless (stringp regexp)
    (error "ELISP:HOW-MANY expects a string, got: ~S" regexp))
  (save-excursion
    (when start (goto-char start))
    (let ((count 0)
          (lim (or end (point-max))))
      (loop while (and (< (point) lim)
                       (re-search-forward regexp lim t))
            do (incf count))
      count)))

(cl:defun count-matches (regexp &optional start end)
  "Bring-up subset of ELisp `count-matches' (alias of `how-many')."
  (how-many regexp start end))

(cl:defun replace-match (replacement &optional _fixedcase literal string subexp)
  "Bring-up subset of ELisp `replace-match'."
  (declare (cl:ignore _fixedcase))
  (unless (stringp replacement)
    (error "ELISP:REPLACE-MATCH expects a string, got: ~S" replacement))
  (let* ((n (or subexp 0))
         (start (match-beginning n))
         (end (match-end n)))
    (unless (and start end)
      (error "ELISP:REPLACE-MATCH no match data"))
    (labels ((replacement-text ()
               (if literal
                   (%elisp-string->cl-string (copy-seq replacement))
                   (let* ((rep (%elisp-string->cl-string replacement))
                          (len (length rep)))
                     (cl:with-output-to-string (out)
                       (loop for i from 0 below len do
                         (let ((ch (char rep i)))
                           (cond
                            ((char/= ch #\\)
                             (write-char ch out))
                            (t
                             (incf i)
                             (when (>= i len)
                               (write-char #\\ out)
                               (return))
                             (let ((esc (char rep i)))
                               (cond
                                ((char= esc #\\) (write-char #\\ out))
                                ((char= esc #\&) (write-string (or (match-string 0 string) "") out))
                                ((digit-char-p esc)
                                 (let* ((j i)
                                        (digits (list esc)))
                                   (loop while (and (< (1+ j) len)
                                                    (digit-char-p (char rep (1+ j))))
                                         do (incf j) (push (char rep j) digits))
                                   (setf i j)
                                   (let* ((num (parse-integer (coerce (nreverse digits) 'cl:string)))
                                          (ms (match-string num string)))
                                     (when ms (write-string (%elisp-string->cl-string ms) out)))))
                                (t
                                 ;; Unknown escape: emit literally.
                                 (write-char #\\ out)
                                 (write-char esc out)))))))))))))
      (cond
       (string
        (unless (stringp string)
          (error "ELISP:REPLACE-MATCH STRING arg must be string, got: ~S" string))
        (let* ((s (%elisp-string->cl-string string))
               (rep (replacement-text)))
          (concatenate 'cl:string (subseq s 0 start) rep (subseq s end))))
       (t
        ;; Buffer replacement.
        (delete-region start end)
        (goto-char start)
        (insert (replacement-text))
        nil)))))

(cl:defun insert (&rest parts)
  (let* ((s0 (apply #'concat parts))
         (s (if (unibyte-string-p s0) (%elisp-string->cl-string s0) s0))
         (txt (elisp-buffer-text *current-buffer*))
         (at (point))
         (idx (1- at)))
    (when (and (uiop:getenv "CLEMACS_PP_DEBUG")
               (> (length s) 0)
               (char= (char s 0) #\Newline))
      (labels ((safe-char (i)
                 (and (<= 0 i) (< i (length txt)) (char txt i)))
               (sym-ch-p (ch)
                 (and ch
                      (or (and (char>= ch #\a) (char<= ch #\z))
                          (and (char>= ch #\A) (char<= ch #\Z))
                          (and (char>= ch #\0) (char<= ch #\9))
                          (char= ch #\:)
                          (char= ch #\-)
                          (char= ch #\_))))
               (snippet (center &key (radius 24))
                 (let* ((s (max 0 (- center radius)))
                        (e (min (length txt) (+ center radius))))
                   (subseq txt s e))))
        (let* ((prev (safe-char (1- idx)))
               (next (safe-char idx)))
          ;; Detect newlines inserted *inside* tokens (pp.el should never do
          ;; this for symbols/keywords; it indicates a scanning/indent bug).
          (when (and (sym-ch-p prev) (sym-ch-p next))
            (let ((path "build/clemacs/tmp/pp-debug.out"))
              (ensure-directories-exist path)
              (with-open-file (out path
                                   :direction :output
                                   :if-exists :append
                                   :if-does-not-exist :create)
                (cl:format out "~&[pp-debug] newline split at pos=~D col=~D buf=~S~%"
                           at (current-column) (elisp-buffer-name *current-buffer*))
                (cl:format out "  before: ~S~%" (snippet (max 0 (- idx 1))))
                (cl:format out "  after:  ~S~%" (snippet idx))
                #+sbcl
                (sb-debug:print-backtrace :stream out :count 50)
                (finish-output out)))))))
    (let ((len (length s)))
      (when (plusp len)
        (let ((intervals (%buffer-text-properties *current-buffer*)))
          (when intervals
            (%set-buffer-text-properties
             *current-buffer*
             (%buffer-intervals-insert intervals at len))))
        (let ((s0-intervals (elisp::%string-text-properties s0)))
          (when s0-intervals
            (let ((buf-intervals nil))
              (dolist (iv s0-intervals)
                (let* ((iv-s (elisp::text-prop-interval-start iv))
                       (iv-e (elisp::text-prop-interval-end iv)))
                  (when (< iv-s iv-e)
                    (push (elisp::make-text-prop-interval
                           :start (+ at iv-s)
                           :end (+ at iv-e)
                           :plist (elisp::text-prop-interval-plist iv))
                          buf-intervals))))
              (when buf-intervals
                (%set-buffer-text-properties
                 *current-buffer*
                 (append (or (%buffer-text-properties *current-buffer*) nil)
                         (nreverse buf-intervals))))))))
      (%buffer-record-insert *current-buffer* at len))
    (setf (elisp-buffer-text *current-buffer*)
          (concatenate 'cl:string (subseq txt 0 idx) s (subseq txt idx)))
    (goto-char (+ (point) (length s)))
    nil))

(cl:defun insert-and-inherit (&rest parts)
  "Bring-up subset of ELisp `insert-and-inherit'."
  (apply #'insert parts))

(cl:defun insert-before-markers-and-inherit (&rest parts)
  "Bring-up subset of ELisp `insert-before-markers-and-inherit'."
  (apply #'insert parts))

(cl:defun insert-file-contents (filename &optional visit beg end replace)
  "Bring-up subset of ELisp `insert-file-contents'."
  (unless (stringp filename)
    (error "ELISP:INSERT-FILE-CONTENTS expects a file name string, got: ~S" filename))
  (when (and beg (not (integerp beg)))
    (error "ELISP:INSERT-FILE-CONTENTS bad BEG: ~S" beg))
  (when (and end (not (integerp end)))
    (error "ELISP:INSERT-FILE-CONTENTS bad END: ~S" end))
  ;; When VISIT is non-nil, Emacs marks the current buffer as visiting FILENAME.
  ;; `find-file-noselect-1' relies on this to set `buffer-file-truename' and
  ;; `default-directory' after reading.
  (when visit
    (set 'buffer-file-name filename))
  (let* ((path (%file-name->cl-string filename))
         (txt (uiop:read-file-string path :external-format :utf-8))
         (b (or beg 0))
         (e (or end (length txt))))
    (unless (<= 0 b e (length txt))
      (error "ELISP:INSERT-FILE-CONTENTS bad range: ~S..~S for ~S" beg end filename))
    (when replace
      (erase-buffer)
      (goto-char (point-min)))
    (let ((chunk (subseq txt b e)))
      (insert chunk)
      ;; Return (FILENAME SIZE).
      (list filename (length chunk)))))

(cl:defun write-region (start end filename &optional append _visit _lockname _mustbenew)
  "Bring-up subset of ELisp `write-region'.

Scope: UTF-8 only (no legacy coding systems)."
  (declare (cl:ignore _visit _lockname _mustbenew))
  (unless (stringp filename)
    (error "ELISP:WRITE-REGION expects a file name string, got: ~S" filename))
  ;; Emacs calls (write-region nil nil FILE ...) from the save-buffer path to
  ;; indicate "write the whole buffer" (not a region); we don't implement
  ;; write-region annotation functions yet, so treat it as point-min..point-max.
  (when (null start)
    (when end
      (error "ELISP:WRITE-REGION nil START requires END=nil, got: ~S" end))
    (setf start (point-min)
          end (point-max)))
  (let* ((path (%file-name->cl-string filename))
         (if-exists (if append :append :supersede)))
    (cond
     ((or (stringp start) (unibyte-string-p start))
      (when end
        (error "ELISP:WRITE-REGION string START requires END=nil, got: ~S" end))
      (if (unibyte-string-p start)
          (let ((octets start))
            (with-open-file (out path
                                 :direction :output
                                 :if-exists if-exists
                                 :if-does-not-exist :create
                                 :element-type '(unsigned-byte 8))
              (loop for b across octets do
                (write-byte b out))))
          (with-open-file (out path
                               :direction :output
                               :if-exists if-exists
                               :if-does-not-exist :create
                               :external-format :utf-8)
            (write-string start out))))
     ((or (integerp start) (elisp-marker-p start))
      (unless (or (integerp end) (elisp-marker-p end))
        (error "ELISP:WRITE-REGION region START requires numeric END, got: ~S" end))
      (let* ((a (%pos start))
             (b (%pos end))
             (lo (min a b))
             (hi (max a b))
             (txt (elisp-buffer-text *current-buffer*))
             (lo-idx (1- lo))
             (hi-idx (1- hi)))
        (unless (<= 0 lo-idx hi-idx (length txt))
          (error "ELISP:WRITE-REGION bad range: ~S..~S" start end))
        (with-open-file (out path
                             :direction :output
                             :if-exists if-exists
                             :if-does-not-exist :create
                             :external-format :utf-8)
          (write-string (subseq txt lo-idx hi-idx) out))))
     (t
      (error "ELISP:WRITE-REGION bad START: ~S" start))))
  nil)

(cl:defun newline (&optional n)
  "Bring-up subset of ELisp `newline'."
  (let ((n (or n 1)))
    (unless (and (integerp n) (>= n 0))
      (error "ELISP:NEWLINE bad arg: ~S" n))
    (dotimes (_ n)
      (insert #\Newline))
    nil))

(cl:defun buffer-string ()
  "Bring-up subset of ELisp `buffer-string'."
  (let* ((txt (elisp-buffer-text *current-buffer*))
         (s (copy-seq txt))
         (intervals (%buffer-text-properties *current-buffer*)))
    (elisp::%clear-string-text-properties s)
    (when intervals
      (elisp::%set-string-text-properties
       s
       (loop for iv in intervals
             for iv-s = (elisp::text-prop-interval-start iv)
             for iv-e = (elisp::text-prop-interval-end iv)
             collect (elisp::make-text-prop-interval
                      :start (1- iv-s)
                      :end (1- iv-e)
                      :plist (elisp::text-prop-interval-plist iv)))))
    s))

(cl:defun bobp ()
  "Bring-up subset of ELisp `bobp'."
  (= (point) (point-min)))

(cl:defun eobp ()
  "Bring-up subset of ELisp `eobp'."
  (= (point) (point-max)))

(cl:defun char-after (&optional pos)
  "Bring-up subset of ELisp `char-after'."
  (let* ((p (if pos (%pos pos) (point))))
    (when (and (integerp p) (<= (point-min) p) (< p (point-max)))
      (char-code (char (elisp-buffer-text *current-buffer*) (1- p))))))

(cl:defun char-before (&optional pos)
  "Bring-up subset of ELisp `char-before'."
  (let* ((p (if pos (%pos pos) (point))))
    (when (and (integerp p) (< (point-min) p) (<= p (point-max)))
      (char-code (char (elisp-buffer-text *current-buffer*) (- p 2))))))

(cl:defun following-char ()
  "Bring-up subset of ELisp `following-char'."
  (or (char-after) 0))

(cl:defun preceding-char ()
  "Bring-up subset of ELisp `preceding-char'."
  (or (char-before) 0))

(cl:defun bolp ()
  "Bring-up subset of ELisp `bolp'."
  (or (bobp)
      (let ((c (char-before)))
        (and c (= c (char-code #\Newline))))))

(cl:defun eolp ()
  "Bring-up subset of ELisp `eolp'."
  (or (eobp)
      (let ((c (char-after)))
        (and c (= c (char-code #\Newline))))))

(cl:defun invisible-p (pos-or-prop &optional _window)
  "Bring-up subset of ELisp `invisible-p'."
  (declare (cl:ignore _window))
  (when (or (integerp pos-or-prop) (elisp-marker-p pos-or-prop))
    (let ((v (get-text-property pos-or-prop 'invisible)))
      (and v t))))

(cl:defun %char-in-skip-set-p (ch set invertp)
  (let ((in (find ch set :test #'char=)))
    (if invertp (not in) (and in t))))

(cl:defun skip-chars-forward (chars &optional limit)
  "Bring-up subset of ELisp `skip-chars-forward'."
  (unless (stringp chars)
    (error "ELISP:SKIP-CHARS-FORWARD expects a string, got: ~S" chars))
  (let* ((set (%elisp-string->cl-string chars))
         (invertp (and (> (length set) 0) (char= (char set 0) #\^)))
         (set (if invertp (subseq set 1) set))
         (stop (or limit (point-max)))
         (pos (point))
         (moved 0))
    (loop while (and (< pos stop)
                     (let ((c (char-after pos)))
                       (and c (%char-in-skip-set-p (code-char c) set invertp))))
          do (incf pos) (incf moved))
    (goto-char pos)
    moved))

(cl:defun skip-chars-backward (chars &optional limit)
  "Bring-up subset of ELisp `skip-chars-backward'."
  (unless (stringp chars)
    (error "ELISP:SKIP-CHARS-BACKWARD expects a string, got: ~S" chars))
  (let* ((set (%elisp-string->cl-string chars))
         (invertp (and (> (length set) 0) (char= (char set 0) #\^)))
         (set (if invertp (subseq set 1) set))
         (stop (or limit (point-min)))
         (pos (point))
         (moved 0))
    (loop while (and (> pos stop)
                     (let ((c (char-before pos)))
                       (and c (%char-in-skip-set-p (code-char c) set invertp))))
          do (decf pos) (incf moved))
    (goto-char pos)
    moved))

(cl:defun %syntax-w_-p (ch)
  ;; Pragmatic approximation for Emacs `\\sw' and `\\s_' classes in
  ;; `emacs-lisp-mode-syntax-table': include alnum plus common symbol chars.
  (or (alphanumericp ch)
      (find ch "_-:" :test #'char=)))

(cl:defun skip-syntax-forward (syntax &optional limit)
  "Bring-up subset of ELisp `skip-syntax-forward'.

Only supports the `w' and `_` classes (and negation with `^`), which is enough
for upstream ERT's `ert--make-xrefs-region'."
  (unless (stringp syntax)
    (error "ELISP:SKIP-SYNTAX-FORWARD expects a string, got: ~S" syntax))
  (let* ((spec (%elisp-string->cl-string syntax))
         (invertp (and (> (length spec) 0) (char= (char spec 0) #\^)))
         (classes (if invertp (subseq spec 1) spec))
         (stop (or limit (point-max)))
         (pos (point))
         (moved 0))
    (labels ((in-classes-p (ch)
               (let ((ok nil))
                 (loop for c across classes do
                   (when (or (and (char= c #\w) (%syntax-w_-p ch))
                             (and (char= c #\_) (%syntax-w_-p ch)))
                     (setf ok t) (return)))
                 (if invertp (not ok) ok))))
      (loop while (and (< pos stop)
                       (let ((c (char-after pos)))
                         (and c (in-classes-p (code-char c)))))
            do (incf pos) (incf moved)))
    (goto-char pos)
    moved))

(cl:defun skip-syntax-backward (syntax &optional limit)
  "Bring-up subset of ELisp `skip-syntax-backward'."
  (unless (stringp syntax)
    (error "ELISP:SKIP-SYNTAX-BACKWARD expects a string, got: ~S" syntax))
  (let* ((spec (%elisp-string->cl-string syntax))
         (invertp (and (> (length spec) 0) (char= (char spec 0) #\^)))
         (classes (if invertp (subseq spec 1) spec))
         (stop (or limit (point-min)))
         (pos (point))
         (moved 0))
    (labels ((in-classes-p (ch)
               (let ((ok nil))
                 (loop for c across classes do
                   (when (or (and (char= c #\w) (%syntax-w_-p ch))
                             (and (char= c #\_) (%syntax-w_-p ch)))
                     (setf ok t) (return)))
                 (if invertp (not ok) ok))))
      (loop while (and (> pos stop)
                       (let ((c (char-before pos)))
                         (and c (in-classes-p (code-char c)))))
            do (decf pos) (incf moved)))
    (goto-char pos)
    moved))

(cl:defun search-backward (needle &optional bound noerror _count)
  "Bring-up subset of ELisp `search-backward'."
  (declare (cl:ignore _count))
  (unless (stringp needle)
    (error "ELISP:SEARCH-BACKWARD expects a string, got: ~S" needle))
  (let* ((n (%elisp-string->cl-string needle))
         (txt (elisp-buffer-text *current-buffer*))
         (end (1- (point)))
         (bnd (max (point-min) (if bound (%pos bound) (point-min))))
         (bnd-idx (1- bnd)))
    (let ((idx (search n txt :start2 bnd-idx :end2 end :from-end t :test #'char=)))
      (cond
       ((null idx)
        (if noerror nil (error "ELISP:SEARCH-BACKWARD not found: ~S" needle)))
       (t
        (goto-char (1+ idx))
        (point))))))

(cl:defvar isearch-string nil)

(cl:defun %clemacs--string-empty-p (s)
  (and (stringp s) (cl:<= (length s) 0)))

(cl:defun %clemacs--isearch-read (prompt)
  (let ((s (read-from-minibuffer (string-to-unibyte prompt))))
    (if (and (stringp s) (not (%clemacs--string-empty-p s)))
        s
        nil)))

(cl:defun isearch-forward (&optional _regexp-p _no-recursive-edit)
  "Bring-up isearch slice: prompt for a literal string and search forward.

This is intentionally not a full incremental isearch implementation yet; it is
enough to support core terminal editing workflows (C-s / C-r)."
  (declare (cl:ignore _regexp-p _no-recursive-edit))
  (let* ((reusep (and (boundp 'last-command) (eq last-command 'isearch-forward)
                      (stringp isearch-string) (not (%clemacs--string-empty-p isearch-string))))
         (needle (or (and reusep isearch-string)
                     (%clemacs--isearch-read "I-search: "))))
    (when (null needle)
      (return-from isearch-forward nil))
    (setf isearch-string needle)
    (if (search-forward needle nil t)
        t
        (progn
          (ding)
          (ignore-errors (message "Failing I-search: %s" needle))
          nil))))

(cl:defun isearch-backward (&optional _regexp-p _no-recursive-edit)
  "Bring-up isearch slice: prompt for a literal string and search backward."
  (declare (cl:ignore _regexp-p _no-recursive-edit))
  (let* ((reusep (and (boundp 'last-command) (eq last-command 'isearch-backward)
                      (stringp isearch-string) (not (%clemacs--string-empty-p isearch-string))))
         (needle (or (and reusep isearch-string)
                     (%clemacs--isearch-read "I-search backward: "))))
    (when (null needle)
      (return-from isearch-backward nil))
    (setf isearch-string needle)
    (if (search-backward needle nil t 1)
        t
        (progn
          (ding)
          (ignore-errors (message "Failing I-search backward: %s" needle))
          nil))))

(cl:defun %clemacs--query-replace-confirm (from to)
  (let ((prompt
          (string-to-unibyte
           (cl:format nil "Replace ~A with ~A? (y or n) "
                      (%elisp-string->cl-string from)
                      (%elisp-string->cl-string to)))))
    (cond
     ((and (boundp 'noninteractive) noninteractive) t)
     (t
      (let ((ans (read-from-minibuffer prompt)))
        (and (stringp ans)
             (not (%clemacs--string-empty-p ans))
             (let ((ch (char (%elisp-string->cl-string ans) 0)))
               (or (char= ch #\y) (char= ch #\Y)))))))))

(cl:defun query-replace (from to &optional _delimited start end _backward _region-noncontiguous-p)
  "Bring-up subset of ELisp `query-replace' (literal string, TTY-only prompts)."
  (declare (cl:ignore _delimited _backward _region-noncontiguous-p))
  (let* ((from (or from (%clemacs--isearch-read "Query replace: ")))
         (to (or to (%clemacs--isearch-read
                     (cl:format nil "Query replace ~A with: " (and from (%elisp-string->cl-string from))))))
         (start (or start (point)))
         (limit (or end (point-max))))
    (when (or (null from) (null to))
      (return-from query-replace 0))
    (goto-char start)
    (let ((count 0))
      (loop while (and (< (point) limit)
                       (search-forward from limit t))
            do
              (let* ((ms (match-beginning 0))
                     (me (match-end 0)))
                (when (and ms me)
                  (goto-char ms)
                  (if (%clemacs--query-replace-confirm from to)
                      (progn
                        (replace-match to nil t)
                        (incf count)
                        (setf limit (point-max)))
                      (goto-char me)))))
      (ignore-errors (message "Replaced %d occurrence%s" count (if (= count 1) "" "s")))
      count)))

(cl:defun replace-string (from to &optional delimited start end backward _region-noncontiguous-p)
  "Bring-up subset of ELisp `replace-string' (literal string)."
  (declare (cl:ignore delimited backward _region-noncontiguous-p))
  (let* ((from (or from (%clemacs--isearch-read "Replace string: ")))
         (to (or to (%clemacs--isearch-read
                     (cl:format nil "Replace string ~A with: "
                                (and from (%elisp-string->cl-string from))))))
         (start (or start (point)))
         (limit (or end (point-max))))
    (when (or (null from) (null to))
      (when (and (boundp 'noninteractive) noninteractive)
        (error "ELISP:REPLACE-STRING noninteractive needs FROM and TO"))
      (return-from replace-string 0))
    (goto-char start)
    (let ((count 0))
      (loop while (and (< (point) limit)
                       (search-forward from limit t))
            do
              (replace-match to nil t)
              (incf count)
              (setf limit (point-max)))
      (ignore-errors (message "Replaced %d occurrence%s" count (if (= count 1) "" "s")))
      count)))

(cl:defun scroll-down-command (&optional arg)
  "Bring-up subset of ELisp `scroll-down-command'."
  (let* ((n (and arg (- (prefix-numeric-value arg)))))
    (cond
     ((fboundp 'scroll-up-command)
      (scroll-up-command n))
     (t
      (ignore-errors (message "scroll-down-command: not implemented")))))
  nil)

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Ensure these show up as commands in `M-x` completions.
  (ignore-errors (function-put 'isearch-forward 'interactive-form '(interactive)))
  (ignore-errors (function-put 'isearch-backward 'interactive-form '(interactive)))
  (ignore-errors (function-put 'query-replace 'interactive-form '(interactive (list nil nil))))
  (ignore-errors (function-put 'replace-string 'interactive-form '(interactive (list nil nil))))
  (ignore-errors (function-put 'scroll-down-command 'interactive-form '(interactive))))

(cl:defun isearch-search ()
  "Bring-up stub for `isearch-search'.

This is defined in upstream `lisp/isearch.el', but is referenced earlier in
that file before its definition, leading to noisy SBCL forward-reference
warnings while compiling under clemacs.

Interactive incremental search is not supported yet."
  (error "ELISP:ISEARCH-SEARCH not implemented"))

(cl:defun number-at-point ()
  "Bring-up subset of ELisp `number-at-point'."
  (let* ((txt (elisp-buffer-text *current-buffer*))
         (len (length txt))
         (p (point))
         (p0 (1- p)))
    (labels ((digitp (ch)
               (and ch (char<= #\0 ch) (char<= ch #\9)))
             (safe-char (i)
               (and (<= 0 i) (< i len) (char txt i))))
      (let ((pos
              (cond
               ((digitp (safe-char p0)) p0)
               ((digitp (safe-char (1- p0))) (1- p0))
               (t nil))))
        (when (null pos)
          (return-from number-at-point nil))
        (let ((start pos)
              (end (1+ pos)))
          (loop while (digitp (safe-char (1- start))) do (decf start))
          (let ((sign (safe-char (1- start))))
            (when (and sign (or (char= sign #\+) (char= sign #\-)))
              (decf start)))
          (loop while (digitp (safe-char end)) do (incf end))
          (let ((s (subseq txt start end)))
            (ignore-errors (cl:parse-integer s))))))))

(cl:defun scan-sexps (from count)
  "Bring-up subset of ELisp `scan-sexps'."
  (unless (integerp count)
    (error "ELISP:SCAN-SEXPS expects integer COUNT, got: ~S" count))
  (let ((from (%pos from)))
    (unless (integerp from)
      (error "ELISP:SCAN-SEXPS expects integer/marker FROM, got: ~S" from))
  (when (zerop count)
    (return-from scan-sexps from))
  (when (minusp count)
    (error "ELISP:SCAN-SEXPS negative COUNT not supported: ~S" count))
	  (let ((txt (elisp-buffer-text *current-buffer*))
	        (pos from))
	    (labels ((whitespacep (ch)
	               (or (char= ch #\Space)
	                   (char= ch #\Tab)
	                   (char= ch #\Return)
	                   (char= ch #\Newline)))
	             (atom-delim-p (ch)
	               (or (whitespacep ch)
	                   (find ch "()[]{}\"" :test #'char=)))
	             (peek (p)
	               (when (and (<= (point-min) p) (< p (point-max)))
	                 (char txt (1- p))))
	             (skip-ws ()
	               (loop for ch = (peek pos)
	                     while (and ch (whitespacep ch)) do
	                       (incf pos)))
             (scan-string ()
               ;; starting at opening quote
               (incf pos) ; skip initial "
               (loop for ch = (peek pos) while ch do
                 (cond
                  ((char= ch #\\) (incf pos 2))
                  ((char= ch #\") (incf pos) (return))
                  (t (incf pos)))))
             (scan-delims (open close)
               (declare (cl:ignore open))
               (let ((stack (list close)))
                 (incf pos) ; skip OPEN
                 (loop while stack do
                   (let ((ch (peek pos)))
                     (when (null ch) (return-from scan-sexps nil))
                     (cond
                      ((char= ch #\") (scan-string))
                      ((char= ch #\() (push #\) stack) (incf pos))
                      ((char= ch #\[) (push #\] stack) (incf pos))
                      ((char= ch #\{) (push #\} stack) (incf pos))
                      ((find ch ")]}" :test #'char=)
                       (unless (char= ch (car stack))
                         (return-from scan-sexps nil))
                       (pop stack)
                       (incf pos))
                      (t (incf pos)))))))
	             (scan-atom ()
	               (loop for ch = (peek pos)
	                     while (and ch (not (atom-delim-p ch))) do
	                       (incf pos)))
	             (scan-one ()
	               (skip-ws)
	               (let ((ch (peek pos)))
	                 (when (null ch) (return-from scan-sexps nil))
	                 (cond
	                  ((find ch "'`,#" :test #'char=) (incf pos) (scan-one))
	                  ((char= ch #\") (scan-string))
	                  ((char= ch #\() (scan-delims #\( #\)))
	                  ((char= ch #\[) (scan-delims #\[ #\]))
	                  ((char= ch #\{) (scan-delims #\{ #\}))
	                  ;; Treat closing delimiters as a 1-char sexp so callers like
	                  ;; pp.el's pp-fill don't get stuck when scanning at ")...".
	                  ((find ch ")]}" :test #'char=) (incf pos))
	                  (t (scan-atom))))))
      (dotimes (i count)
        (declare (ignorable i))
        (scan-one))
      (when (and (uiop:getenv "CLEMACS_PP_TRACE_SCAN_SEXPS")
                 (= count 1))
        (labels ((peek* (p)
                   (when (and (<= (point-min) p) (< p (point-max)))
                     (char txt (1- p)))))
          (let ((c0 (peek* from))
                (c1 (peek* (1+ from))))
            (when (and c0 c1 (char= c0 #\:) (alphanumericp c1))
              (let ((path "build/clemacs/tmp/scan-sexps-debug.out"))
                (ensure-directories-exist path)
                (with-open-file (out path
                                     :direction :output
                                     :if-exists :append
                                     :if-does-not-exist :create)
                  (cl:format out "~&scan-sexps from=~D => ~D ; token=~S~%"
                             from pos
                             (subseq txt (1- from) (max 0 (min (length txt) (1- pos)))))
                  #+sbcl
                  (sb-debug:print-backtrace :stream out :count 20)
                  (finish-output out))))))))
      pos)))

(cl:defun forward-sexp (&optional n)
  "Bring-up subset of the C primitive `forward-sexp'."
  (let ((n (or n 1)))
    (unless (integerp n)
      (error "ELISP:FORWARD-SEXP bad arg: ~S" n))
    (when (zerop n)
      (return-from forward-sexp nil))
    (when (minusp n)
      (error "ELISP:FORWARD-SEXP negative N not supported yet: ~S" n))
    (let ((pos (scan-sexps (point) n)))
      (when (integerp pos)
        (goto-char pos)))
    nil))

(cl:defun %column-at-pos (pos)
  (let ((saved (point)))
    (unwind-protect
        (progn (goto-char pos) (current-column))
      (goto-char saved))))

(cl:defun indent-according-to-mode ()
  "Bring-up subset of ELisp `indent-according-to-mode'."
  (when indent-line-function
    (funcall indent-line-function))
  nil)

(cl:defun set-buffer-major-mode (&optional _buffer)
  "Bring-up stub for ELisp `set-buffer-major-mode'."
  (declare (cl:ignore _buffer))
  ;; Prefer a stable, TTY-safe default until mode machinery is implemented.
  (when (boundp 'major-mode)
    (setf major-mode 'fundamental-mode))
  nil)

(cl:defun indent-rigidly (start end columns)
  "Bring-up subset of ELisp `indent-rigidly'."
  (let* ((s (%pos start))
         (e (%pos end))
         (cols columns))
    (unless (and (integerp cols) (<= 0 cols))
      (error "ELISP:INDENT-RIGIDLY bad columns: ~S" columns))
    (when (> s e)
      (error "ELISP:INDENT-RIGIDLY start > end: ~S ~S" start end))
    (when (zerop cols)
      (return-from indent-rigidly nil))
    ;; Emacs indents lines whose beginning falls within START..END.
    ;; In particular, if START is in the middle of a line, that line is not
    ;; indented (which is important for pp.el's use of indent-rigidly).
    (let* ((txt (elisp-buffer-text *current-buffer*))
           (pad (cl:make-string cols :initial-element #\Space))
           (insert-pos nil)
           (p0 (point)))
      ;; If START is exactly at BOL, include it.
      (when (or (= s (point-min))
                (let ((c (char-before s)))
                  (and c (= c (char-code #\Newline)))))
        (push s insert-pos))
      ;; Include each line start after a newline within the region.
      (let ((idx (1- s))
            (end-idx (max 0 (1- e))))
        (loop for nl = (cl:position #\Newline txt :start idx :end end-idx)
              while nl do
                (let ((ls (+ nl 2)))
                  (when (and (<= s ls) (< ls e))
                    (push ls insert-pos)))
                (setf idx (1+ nl))))
      (when insert-pos
        ;; Apply inserts from the end so earlier recorded positions remain
        ;; stable. This keeps markers consistent as well.
        (dolist (pos (sort insert-pos #'>))
          (goto-char pos)
          (insert pad))
        (let ((n (count-if (lambda (pos) (<= pos p0)) insert-pos)))
          (goto-char (+ p0 (* cols n))))))
    nil))

(cl:defun erase-buffer ()
  "Bring-up subset of ELisp `erase-buffer'."
  (delete-region (point-min) (point-max))
  (goto-char (point-min))
  nil)

(cl:defun buffer-disable-undo (&optional _buffer)
  "Bring-up stub for ELisp `buffer-disable-undo'."
  (declare (cl:ignore _buffer))
  nil)

(cl:defun buffer-name (&optional buffer)
  "Bring-up subset of ELisp `buffer-name'."
  (let ((buf (or buffer *current-buffer*)))
    (etypecase buf
      (elisp-buffer (elisp-buffer-name buf))
      (null nil))))

(cl:defun buffer-file-name (&optional buffer)
  "Bring-up subset of the C primitive `buffer-file-name'."
  (let ((buf (or buffer *current-buffer*)))
    (cond
     ((null buf) nil)
     ((not (elisp-buffer-p buf))
      (error "ELISP:BUFFER-FILE-NAME expected buffer, got: ~S" buf))
     (t
      (buffer-local-value 'buffer-file-name buf)))))

(cl:defun buffer-modified-p (&optional buffer)
  "Bring-up subset of ELisp `buffer-modified-p'."
  (let ((buf (or buffer *current-buffer*)))
    (unless (elisp-buffer-p buf)
      (error "ELISP:BUFFER-MODIFIED-P expected buffer, got: ~S" buf))
    (elisp-buffer-modified-p buf)))

(cl:defun set-buffer-modified-p (flag)
  "Bring-up subset of ELisp `set-buffer-modified-p'."
  (setf (elisp-buffer-modified-p *current-buffer*) (and flag t))
  flag)

(cl:defun restore-buffer-modified-p (flag)
  "Bring-up stub for ELisp `restore-buffer-modified-p'."
  (set-buffer-modified-p flag))

(cl:defvar global-mark-ring nil)
(cl:defvar mark-ring nil)
(cl:defvar mark-active nil)
(cl:defvar transient-mark-mode nil)
(cl:defvar inhibit-modification-hooks nil)
(cl:defvar inhibit-read-only nil)
(cl:defvar buffer-read-only nil)

(cl:defun barf-if-buffer-read-only (&optional _pos)
  "Bring-up subset of the C primitive `barf-if-buffer-read-only'."
  (declare (cl:ignore _pos))
  (when (and buffer-read-only (not inhibit-read-only))
    (signal 'buffer-read-only (list (current-buffer))))
  nil)

(defstruct elisp-window
  (buffer nil)
  (start nil)
  (parameters nil))

(defstruct elisp-frame
  (selected-window nil))

(cl:defvar *single-window*
  (make-elisp-window :buffer *current-buffer*
                     :start (point-min)))
(cl:defvar *minibuffer-window*
  (make-elisp-window :buffer nil
                     :start 1))
(cl:defvar *windows* (list *single-window*))
(cl:defvar *selected-window* *single-window*)
(cl:defvar *single-frame* (make-elisp-frame :selected-window *single-window*))
(cl:defvar *selected-frame* *single-frame*)

(cl:defvar frame-internal-parameters nil)

(cl:defvar *frame-parameters*
  (cl:make-hash-table :test 'eq))

(cl:defun %frame-parameters--key (frame)
  (cond
   ((null frame) (selected-frame))
   ((framep frame) frame)
   (t frame)))

(cl:defun frame-parameter (frame parameter)
  "Bring-up subset of the C primitive `frame-parameter' (single-frame)."
  (let ((plist (gethash (%frame-parameters--key frame) *frame-parameters*)))
    (plist-get plist parameter)))

(cl:defun frame-parameters (&optional frame)
  "Bring-up subset of the C primitive `frame-parameters' (single-frame)."
  (let ((plist (gethash (%frame-parameters--key frame) *frame-parameters*)))
    (let ((out nil))
      (loop for (k v) on plist by #'cddr do
        (push (cons k v) out))
      (nreverse out))))

(cl:defun modify-frame-parameters (frame alist)
  "Bring-up subset of ELisp `modify-frame-parameters' (single-frame)."
  (let* ((key (%frame-parameters--key frame))
         (plist (gethash key *frame-parameters*)))
    (dolist (cell alist)
      (when (consp cell)
        (setf plist (plist-put plist (car cell) (cdr cell)))))
    (setf (gethash key *frame-parameters*) plist))
  nil)

(cl:defvar *terminal-parameters*
  (cl:make-hash-table :test 'eq))

(cl:defun %terminal-parameters--key (terminal)
  (cond
   ((null terminal) (selected-frame))
   ((framep terminal) terminal)
   (t terminal)))

(cl:defun terminal-parameter (terminal parameter)
  "Bring-up subset of ELisp `terminal-parameter'."
  (plist-get (gethash (%terminal-parameters--key terminal) *terminal-parameters*) parameter))

(cl:defun set-terminal-parameter (terminal parameter value)
  "Bring-up subset of ELisp `set-terminal-parameter' (returns old value)."
  (let* ((key (%terminal-parameters--key terminal))
         (plist (gethash key *terminal-parameters*))
         (old (plist-get plist parameter)))
    (setf (gethash key *terminal-parameters*)
          (plist-put plist parameter value))
    old))

(cl:defun set-input-mode (&rest _args)
  "Bring-up stub for ELisp `set-input-mode'."
  (declare (cl:ignore _args))
  nil)

(cl:defun windowp (object)
  "Bring-up subset of ELisp `windowp' (single-window)."
  (and (elisp-window-p object) t))

(cl:defun window-valid-p (object)
  "Bring-up subset of the C primitive `window-valid-p'."
  (and (window-live-p object) t))

(cl:defun framep (object)
  "Bring-up subset of ELisp `framep' (single-frame)."
  (and (elisp-frame-p object) t))

(cl:defun selected-frame ()
  "Bring-up subset of ELisp `selected-frame' (single-frame)."
  *selected-frame*)

(cl:defun frame-list (&optional _terminal)
  "Bring-up subset of the C primitive `frame-list' (single-frame)."
  (declare (cl:ignore _terminal))
  (list (selected-frame)))

(cl:defun make-frame (&optional _parameters)
  "Bring-up stub for the C primitive `make-frame' (TTY single-frame)."
  (declare (cl:ignore _parameters))
  (selected-frame))

(cl:defun frame-char-width (&optional _frame)
  "Bring-up stub for the C primitive `frame-char-width'."
  (declare (cl:ignore _frame))
  1)

(cl:defun frame-char-height (&optional _frame)
  "Bring-up stub for the C primitive `frame-char-height'."
  (declare (cl:ignore _frame))
  1)

(cl:defun frame-right-divider-width (&optional _frame)
  "Bring-up stub for the C primitive `frame-right-divider-width' (TTY)."
  (declare (cl:ignore _frame))
  0)

(cl:defun frame-bottom-divider-width (&optional _frame)
  "Bring-up stub for the C primitive `frame-bottom-divider-width' (TTY)."
  (declare (cl:ignore _frame))
  0)

(cl:defun frame-internal-border-width (&optional _frame)
  "Bring-up stub for the C primitive `frame-internal-border-width' (TTY)."
  (declare (cl:ignore _frame))
  0)

(cl:defun frame-char-size (&optional frame horizontal)
  "Bring-up subset of the C primitive `frame-char-size' (TTY)."
  (declare (cl:ignore frame))
  (if horizontal
      (frame-char-width)
      (frame-char-height)))

(cl:defun scroll-bar-scale (&rest _args)
  "Bring-up stub for ELisp `scroll-bar-scale' (no scroll bars)."
  (declare (cl:ignore _args))
  nil)

(cl:defun terminal-live-p (&optional _terminal)
  "Bring-up stub for the C primitive `terminal-live-p' (single TTY)."
  (declare (cl:ignore _terminal))
  ;; Emacs's `terminal-live-p` returns non-nil for the selected terminal when
  ;; passed nil.  Returning t here avoids frame.el display helpers walking
  ;; terminal/frame lists we don't model yet.
  t)

(cl:defun window-fringes (&optional _window)
  "Bring-up stub for the C primitive `window-fringes' (TTY; no fringes)."
  (declare (cl:ignore _window))
  ;; Return (LEFT RIGHT OUTSIDE-MARGINS . ...).  Callers typically look at the
  ;; first two elements.
  (list 0 0 0 0))

(cl:defun window-current-scroll-bars (&optional _window)
  "Bring-up stub for the C primitive `window-current-scroll-bars' (no scroll bars)."
  (declare (cl:ignore _window))
  (cons nil nil))

(cl:defun window-scroll-bar-width (&optional _window)
  "Bring-up stub for the C primitive `window-scroll-bar-width' (TTY; no scroll bars)."
  (declare (cl:ignore _window))
  0)

(cl:defun window-margins (&optional _window)
  "Bring-up stub for the C primitive `window-margins' (TTY; no margins)."
  (declare (cl:ignore _window))
  (cons nil nil))

(cl:defun window-header-line-height (&optional _window)
  "Bring-up stub for the C primitive `window-header-line-height' (TTY)."
  (declare (cl:ignore _window))
  0)

(cl:defun window-pixel-left (&optional _window)
  "Bring-up stub for the C primitive `window-pixel-left' (single-window, TTY)."
  (declare (cl:ignore _window))
  0)

(cl:defun window-pixel-top (&optional _window)
  "Bring-up stub for the C primitive `window-pixel-top' (single-window, TTY)."
  (declare (cl:ignore _window))
  0)

(cl:defun window-left-column (&optional _window)
  "Bring-up stub for the C primitive `window-left-column' (single-window, TTY)."
  (declare (cl:ignore _window))
  0)

(cl:defun window-top-line (&optional _window)
  "Bring-up stub for the C primitive `window-top-line' (single-window, TTY)."
  (declare (cl:ignore _window))
  1)

(cl:defun frame-live-p (frame)
  "Bring-up subset of ELisp `frame-live-p' (single-frame)."
  (and (elisp-frame-p frame) (eq frame *single-frame*)))

(cl:defun window-frame (&optional window)
  "Bring-up subset of ELisp `window-frame' (single-window)."
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-FRAME expected live window, got: ~S" w))
    (selected-frame)))

(cl:defun window-normalize-frame (frame)
  "Bring-up subset of the C primitive `window-normalize-frame' (single-frame)."
  (cond
   ((null frame) (selected-frame))
   ((framep frame) frame)
   (t (selected-frame))))

(cl:defun frame-selected-window (&optional frame)
  "Bring-up subset of ELisp `frame-selected-window' (single-frame)."
  (let ((f (or frame (selected-frame))))
    (unless (frame-live-p f)
      (error "ELISP:FRAME-SELECTED-WINDOW expected live frame, got: ~S" f))
    (or (elisp-frame-selected-window f) *single-window*)))

(cl:defun frame-root-window (&optional frame)
  "Bring-up subset of the C primitive `frame-root-window' (single-frame)."
  (declare (cl:ignore frame))
  (or (and (consp *windows*) (car *windows*))
      *single-window*))

(cl:defun tty-top-frame (&optional frame)
  "Bring-up subset of ELisp `tty-top-frame' (single-frame)."
  (declare (cl:ignore frame))
  (selected-frame))

(cl:defun select-frame (frame &optional _norecord)
  "Bring-up subset of ELisp `select-frame' (single-frame)."
  (declare (cl:ignore _norecord))
  (unless (frame-live-p frame)
    (error "ELISP:SELECT-FRAME expected live frame, got: ~S" frame))
  (setf *selected-frame* frame)
  (select-window (frame-selected-window frame) 'norecord)
  frame)

(cl:defun selected-window ()
  "Bring-up subset of ELisp `selected-window'."
  *selected-window*)

(cl:defmacro save-selected-window (&body body)
  "Bring-up subset of ELisp `save-selected-window'."
  (let ((saved (cl:gensym "SAVED-WIN-")))
    `(let ((,saved (selected-window)))
       (unwind-protect
           (progn ,@body)
         (select-window ,saved)))))

(cl:defmacro with-selected-window (window &body body)
  "Bring-up subset of ELisp `with-selected-window' (single-window)."
  `(save-selected-window
     (select-window ,window)
     ,@body))

(cl:defun window-live-p (window)
  "Bring-up subset of ELisp `window-live-p'."
  (and (elisp-window-p window)
       (or (eq window *minibuffer-window*)
           (and (consp *windows*) (cl:member window *windows* :test #'eq) t))))

(cl:defun window-list (&optional _frame minibuffer _start-window)
  "Bring-up subset of ELisp `window-list'."
  (declare (cl:ignore _frame _start-window))
  (append (or *windows* nil)
          (when minibuffer (list (minibuffer-window)))))

(cl:defun next-window (&optional window minibuffer _all-frames)
  "Bring-up subset of the C primitive `next-window'."
  (declare (cl:ignore _all-frames))
  (let* ((w (or window (selected-window)))
         (wins (window-list nil minibuffer nil)))
    (when (null wins)
      (return-from next-window w))
    (let* ((pos (or (cl:position w wins :test #'eq) -1))
           (idx (mod (1+ pos) (length wins))))
      (nth idx wins))))

(cl:defun previous-window (&optional window minibuffer _all-frames)
  "Bring-up subset of the C primitive `previous-window'."
  (declare (cl:ignore _all-frames))
  (let* ((w (or window (selected-window)))
         (wins (window-list nil minibuffer nil)))
    (when (null wins)
      (return-from previous-window w))
    (let* ((pos (or (cl:position w wins :test #'eq) 0))
           (idx (mod (1- pos) (length wins))))
      (nth idx wins))))

(cl:defun one-window-p (&optional no-minibuffer _all-frames)
  "Bring-up subset of ELisp `one-window-p'."
  (declare (cl:ignore _all-frames))
  (and (= (length (or *windows* nil)) 1)
       (or (not no-minibuffer)
           (not (active-minibuffer-window)))))

(cl:defun window-buffer (&optional window)
  "Bring-up subset of ELisp `window-buffer'."
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-BUFFER expected live window, got: ~S" w))
    (elisp-window-buffer w)))

(cl:defun window-parameters (&optional window)
  "Bring-up subset of the C primitive `window-parameters'."
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-PARAMETERS expected live window, got: ~S" w))
    (copy-tree (or (elisp-window-parameters w) nil))))

(cl:defun window-parameter (window parameter)
  "Bring-up subset of the C primitive `window-parameter'."
  (unless (window-live-p window)
    (error "ELISP:WINDOW-PARAMETER expected live window, got: ~S" window))
  (cdr (cl:assoc parameter (or (elisp-window-parameters window) nil) :test #'eq)))

(cl:defun set-window-parameter (window parameter value)
  "Bring-up subset of the C primitive `set-window-parameter'."
  (unless (window-live-p window)
    (error "ELISP:SET-WINDOW-PARAMETER expected live window, got: ~S" window))
  (let* ((plist (or (elisp-window-parameters window) nil))
         (cell (cl:assoc parameter plist :test #'eq)))
    (if cell
        (setf (cdr cell) value)
        (push (cons parameter value) plist))
    (setf (elisp-window-parameters window) plist))
  value)

(cl:defun window-parent (&optional _window)
  "Bring-up stub for the C primitive `window-parent' (no window tree)."
  nil)

(cl:defun window-top-child (&optional _window)
  "Bring-up stub for the C primitive `window-top-child' (no window tree)."
  nil)

(cl:defun window-left-child (&optional _window)
  "Bring-up stub for the C primitive `window-left-child' (no window tree)."
  nil)

(cl:defun window-next-sibling (window)
  "Bring-up subset of the C primitive `window-next-sibling' (window list)."
  (unless (window-live-p window)
    (error "ELISP:WINDOW-NEXT-SIBLING expected live window, got: ~S" window))
  (let* ((wins (or *windows* nil))
         (pos (cl:position window wins :test #'eq)))
    (when (and pos (< (1+ pos) (length wins)))
      (nth (1+ pos) wins))))

(cl:defun window-prev-sibling (window)
  "Bring-up subset of the C primitive `window-prev-sibling' (window list)."
  (unless (window-live-p window)
    (error "ELISP:WINDOW-PREV-SIBLING expected live window, got: ~S" window))
  (let* ((wins (or *windows* nil))
         (pos (cl:position window wins :test #'eq)))
    (when (and pos (> pos 0))
      (nth (1- pos) wins))))

(cl:defun window-dedicated-p (&optional window)
  "Bring-up subset of the C primitive `window-dedicated-p'."
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-DEDICATED-P expected live window, got: ~S" w))
    (or (window-parameter w 'window-dedicated)
        (window-parameter w 'dedicated))))

(cl:defun set-window-dedicated-p (window flag)
  "Bring-up subset of the C primitive `set-window-dedicated-p'."
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:SET-WINDOW-DEDICATED-P expected live window, got: ~S" w))
    ;; Store dedicated state in the window parameters so `window-dedicated-p'
    ;; can observe it (clemacs has no window structure fields yet).
    (set-window-parameter w 'window-dedicated flag)
    flag))

(cl:defun window-edges (&optional _window _body)
  "Bring-up stub for the C primitive `window-edges' (no layout)."
  (list 0 0 (window-width) (window-height)))

(cl:defun window-inside-edges (&optional _window _body)
  "Bring-up stub for the C primitive `window-inside-edges' (no layout)."
  (window-edges))

(cl:defun window-size (&optional window horizontal pixelwise _round)
  "Bring-up subset of the C primitive `window-size' (TTY)."
  (declare (cl:ignore _round))
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-SIZE expected live window, got: ~S" w))
    (let* ((chars
             (handler-case
                 (multiple-value-bind (rows cols) (clemacs::tty-winsize)
                   (let ((v (if horizontal cols rows))
                         (fallback (if horizontal 80 24)))
                     (if (and (integerp v) (> v 0)) v fallback)))
               (cl:error () (if horizontal 80 24)))))
      (if pixelwise
          (* chars (frame-char-size (window-frame w) horizontal))
          chars))))

(cl:defun window-body-width (&optional window pixelwise)
  "Bring-up subset of the C primitive `window-body-width' (TTY).

PIXELWISE can be nil, t, or the symbol `pixel'.  Other non-nil values are
treated as nil."
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-BODY-WIDTH expected live window, got: ~S" w))
    (let* ((pixelp (or (eq pixelwise t) (eq pixelwise 'pixel)))
           (chars (window-total-width w)))
      (if pixelp
          (* chars (frame-char-width (window-frame w)))
        chars))))

(cl:defun window-body-height (&optional window pixelwise)
  "Bring-up subset of the C primitive `window-body-height' (TTY).

PIXELWISE can be nil, t, or the symbol `pixel'.  Other non-nil values are
treated as nil."
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-BODY-HEIGHT expected live window, got: ~S" w))
    (let* ((pixelp (or (eq pixelwise t) (eq pixelwise 'pixel)))
           (chars (window-total-height w)))
      (if pixelp
          (* chars (frame-char-height (window-frame w)))
        chars))))

(cl:defun window-size-fixed-p (&optional window _horizontal)
  "Bring-up stub for the C primitive `window-size-fixed-p' (no fixed windows)."
  (declare (cl:ignore window _horizontal))
  nil)

(cl:defun window-pixel-height (&optional window)
  "Bring-up subset of the C primitive `window-pixel-height' (TTY)."
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-PIXEL-HEIGHT expected live window, got: ~S" w))
    (* (window-total-height w) (frame-char-height (window-frame w)))))

(cl:defun window-pixel-width (&optional window)
  "Bring-up subset of the C primitive `window-pixel-width' (TTY)."
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-PIXEL-WIDTH expected live window, got: ~S" w))
    (* (window-total-width w) (frame-char-width (window-frame w)))))

(cl:defun window-point (&optional window)
  "Bring-up subset of the C primitive `window-point'."
  (let* ((w (or window (selected-window)))
         (buf (and (window-live-p w) (elisp-window-buffer w))))
    (unless (and (window-live-p w) (elisp-buffer-p buf))
      (error "ELISP:WINDOW-POINT expected live window, got: ~S" w))
    (elisp-buffer-point buf)))

(cl:defun set-window-point (window pos)
  "Bring-up subset of ELisp `set-window-point'."
  (unless (window-live-p window)
    (error "ELISP:SET-WINDOW-POINT expected live window, got: ~S" window))
  (let ((buf (elisp-window-buffer window)))
    (unless (elisp-buffer-p buf)
      (error "ELISP:SET-WINDOW-POINT expected window buffer, got: ~S" buf))
    (with-current-buffer buf
      (goto-char pos))))

(cl:defun window-start (&optional window)
  "Bring-up subset of the C primitive `window-start'."
  (let* ((w (or window (selected-window)))
         (buf (and (window-live-p w) (elisp-window-buffer w))))
    (unless (and (window-live-p w) (elisp-buffer-p buf))
      (error "ELISP:WINDOW-START expected live window, got: ~S" w))
    (or (elisp-window-start w)
        (with-current-buffer buf (point-min)))))

(cl:defun window-font-height (&optional _window _face)
  "Bring-up stub for the C primitive `window-font-height' (TTY)."
  (declare (cl:ignore _window _face))
  1)

(cl:defun window-font-width (&optional _window _face)
  "Bring-up stub for the C primitive `window-font-width' (TTY)."
  (declare (cl:ignore _window _face))
  1)

(cl:defun window-end (&optional window _update)
  "Bring-up subset of the C primitive `window-end' (single-window)."
  (declare (cl:ignore _update))
  (let* ((w (or window (selected-window)))
         (buf (and (window-live-p w) (elisp-window-buffer w))))
    (unless (and (window-live-p w) (elisp-buffer-p buf))
      (error "ELISP:WINDOW-END expected live window, got: ~S" w))
    (with-current-buffer buf (point-max))))

(cl:defun set-window-start (window pos &optional _noforce)
  "Bring-up subset of ELisp `set-window-start'."
  (declare (cl:ignore _noforce))
  (unless (window-live-p window)
    (error "ELISP:SET-WINDOW-START expected live window, got: ~S" window))
  (let ((buf (elisp-window-buffer window)))
    (unless (elisp-buffer-p buf)
      (error "ELISP:SET-WINDOW-START expected window buffer, got: ~S" buf))
    (with-current-buffer buf
      (let* ((p (%pos pos))
             (p* (max (point-min) (min p (point-max)))))
        (setf (elisp-window-start window) p*)
        p*))))

(cl:defun window-vscroll (&optional window _pixels-p)
  "Bring-up stub for the C primitive `window-vscroll' (TTY)."
  (declare (cl:ignore _pixels-p))
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-VSCROLL expected live window, got: ~S" w))
    0))

(cl:defun window-hscroll (&optional window)
  "Bring-up stub for the C primitive `window-hscroll' (TTY)."
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:WINDOW-HSCROLL expected live window, got: ~S" w))
    0))

(cl:defun set-window-vscroll (window vscroll &optional _pixels-p)
  "Bring-up stub for the C primitive `set-window-vscroll' (TTY)."
  (declare (cl:ignore vscroll _pixels-p))
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:SET-WINDOW-VSCROLL expected live window, got: ~S" w))
    0))

(cl:defun set-window-hscroll (window columns)
  "Bring-up stub for the C primitive `set-window-hscroll' (TTY)."
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:SET-WINDOW-HSCROLL expected live window, got: ~S" w))
    (unless (integerp columns)
      (error "ELISP:SET-WINDOW-HSCROLL expected integer columns, got: ~S" columns))
    columns))

(cl:defun pos-visible-in-window-p (&optional pos window partially)
  "Bring-up stub for ELisp `pos-visible-in-window-p' (TTY, no layout).

Returns non-nil when POS is within the buffer bounds of WINDOW's buffer.
When PARTIALLY is non-nil and POS is visible, return a small (X Y) list."
  (let* ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:POS-VISIBLE-IN-WINDOW-P expected live window, got: ~S" w))
    (let ((buf (window-buffer w)))
      (unless (bufferp buf)
        (error "ELISP:POS-VISIBLE-IN-WINDOW-P expected window buffer, got: ~S" buf))
      (with-current-buffer buf
        (let ((p* (if pos (%pos pos) (point))))
          (when (<= (point-min) p* (point-max))
            (if partially
                (list 0 0)
                t)))))))

(cl:defun undo-boundary ()
  "Bring-up stub for ELisp `undo-boundary' (no undo list yet)."
  nil)

(cl:defun get-buffer-window (&optional buffer-or-name _frame)
  "Bring-up subset of ELisp `get-buffer-window' (single-window)."
  (declare (cl:ignore _frame))
  (let* ((buf (cond
               ((null buffer-or-name) (current-buffer))
               (t (get-buffer buffer-or-name))))
         (wins (append (or *windows* nil) (list *minibuffer-window*))))
    (when (null buf)
      (return-from get-buffer-window nil))
    (dolist (win wins nil)
      (when (and (window-live-p win) (eq (elisp-window-buffer win) buf))
        (return-from get-buffer-window win)))))

(cl:defun minibuffer-selected-window ()
  "Bring-up subset of ELisp `minibuffer-selected-window' (TTY)."
  (and (boundp '*clemacs-minibuffer-active-p*)
       *clemacs-minibuffer-active-p*
       (boundp '*clemacs-minibuffer-selected-window*)
       *clemacs-minibuffer-selected-window*))

(cl:defun minibuffer-window (&optional frame)
  "Bring-up subset of ELisp `minibuffer-window' (single-frame, TTY)."
  (declare (cl:ignore frame))
  (let ((mbuf (cond
               ((and (boundp '*clemacs-minibuffer-buffer*)
                     (bufferp *clemacs-minibuffer-buffer*))
                *clemacs-minibuffer-buffer*)
               (t
                (get-buffer-create +clemacs-minibuffer-buffer-name+)))))
    (setf (elisp-window-buffer *minibuffer-window*) mbuf)
    (setf (elisp-window-start *minibuffer-window*)
          (with-current-buffer mbuf (point-min)))
    *minibuffer-window*))

(cl:defun active-minibuffer-window ()
  "Bring-up stub for the C primitive `active-minibuffer-window' (TTY)."
  (and (boundp '*clemacs-minibuffer-active-p*)
       *clemacs-minibuffer-active-p*
       (minibuffer-window)))

(cl:defun minibuffer-prompt-end ()
  "Bring-up subset of ELisp `minibuffer-prompt-end'."
  (cond
   ((and (boundp '*clemacs-minibuffer-active-p*)
         *clemacs-minibuffer-active-p*
         (boundp '*clemacs-minibuffer-prompt-end*)
         (integerp *clemacs-minibuffer-prompt-end*))
    *clemacs-minibuffer-prompt-end*)
   (t (point-min))))

(cl:defun window-minibuffer-p (&optional _window)
  "Bring-up subset of ELisp `window-minibuffer-p' (single-frame, TTY)."
  (let ((w (or _window (selected-window))))
    (and (window-live-p w)
         (eq w (minibuffer-window))
         t)))

(cl:defun minibufferp (&optional _buffer _live)
  "Bring-up subset of ELisp `minibufferp' (TTY)."
  (declare (cl:ignore _live))
  (let ((buf (or _buffer (current-buffer))))
    (or (and (boundp '*clemacs-minibuffer-buffer*)
             (bufferp *clemacs-minibuffer-buffer*)
             (eq buf *clemacs-minibuffer-buffer*))
        ;; Pragmatic: treat buffers named like Emacs' minibuffer buffers as minibuffers.
        (and (bufferp buf)
             (stringp (buffer-name buf))
             (if (cl:search " *Minibuf-" (%elisp-string->cl-string (buffer-name buf))
                            :test #'cl:char=)
                 t
                 nil)))))

(cl:defun exit-recursive-edit ()
  "Bring-up stub for the C primitive `exit-recursive-edit'."
  (error "ELISP:EXIT-RECURSIVE-EDIT not in recursive edit"))

(cl:defun buffer-base-buffer (&optional _buffer)
  "Bring-up stub for the C primitive `buffer-base-buffer' (no indirect buffers)."
  (declare (cl:ignore _buffer))
  nil)

(cl:defun posn-at-point (&optional _pos _window)
  "Bring-up stub for the C primitive `posn-at-point'."
  (declare (cl:ignore _pos _window))
  nil)

(cl:defun constrain-to-field (newpos _oldpos &optional _escape-from-edge _only-in-line _inhibit-capture-property)
  "Bring-up subset of the C primitive `constrain-to-field'."
  (declare (cl:ignore _oldpos _escape-from-edge _only-in-line _inhibit-capture-property))
  newpos)

(cl:defun delete-minibuffer-contents ()
  "Bring-up subset of ELisp `delete-minibuffer-contents' (TTY)."
  (when (and (boundp '*clemacs-minibuffer-active-p*)
             *clemacs-minibuffer-active-p*
             (boundp '*clemacs-minibuffer-buffer*)
             (bufferp *clemacs-minibuffer-buffer*))
    (with-current-buffer *clemacs-minibuffer-buffer*
      (delete-region (minibuffer-prompt-end) (point-max))))
  (when (boundp '*clemacs-last-minibuffer-contents*)
    (set '*clemacs-last-minibuffer-contents* (string-to-unibyte "")))
  nil)

(cl:defun exit-minibuffer ()
  "Bring-up subset of ELisp `exit-minibuffer' (TTY)."
  (let ((in-minibuffer-p
          (or (and (boundp '*clemacs-minibuffer-active-p*)
                   *clemacs-minibuffer-active-p*)
              (and (boundp '*clemacs-minibuffer-buffer*)
                   (bufferp *clemacs-minibuffer-buffer*)
                   (eq (current-buffer) *clemacs-minibuffer-buffer*)))))
    (if (and in-minibuffer-p
             (boundp '+clemacs-minibuffer-exit-tag+))
        (cl:throw +clemacs-minibuffer-exit-tag+ (minibuffer-contents))
        (error "ELISP:EXIT-MINIBUFFER not in minibuffer"))))

(cl:defun select-window (window &optional _norecord)
  "Bring-up subset of ELisp `select-window'."
  (declare (cl:ignore _norecord))
  (unless (window-live-p window)
    (error "ELISP:SELECT-WINDOW expected live window, got: ~S" window))
  (setf *selected-window* window)
  (setf (elisp-frame-selected-window *single-frame*) window)
  (let ((buf (elisp-window-buffer window)))
    (when buf
      (set-buffer buf)))
  window)

(cl:defun set-window-buffer (window buffer-or-name &optional _keep-margins)
  "Bring-up subset of the C primitive `set-window-buffer'."
  (declare (cl:ignore _keep-margins))
  (unless (window-live-p window)
    (error "ELISP:SET-WINDOW-BUFFER expected live window, got: ~S" window))
  (let ((buf (or (and buffer-or-name (get-buffer buffer-or-name))
                 (and (stringp buffer-or-name) (get-buffer-create buffer-or-name))
                 (and (bufferp buffer-or-name) buffer-or-name)
                 (error "ELISP:SET-WINDOW-BUFFER invalid buffer: ~S" buffer-or-name))))
    (setf (elisp-window-buffer window) buf
          (elisp-window-start window) (with-current-buffer buf (point-min)))
    (when (eq window (selected-window))
      (set-buffer buf))
    nil))

(cl:defun split-window (&optional window _size _side _pixelwise)
  "Bring-up subset of ELisp `split-window' (no layout; window list only)."
  (declare (cl:ignore _size _side _pixelwise))
  (let* ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:SPLIT-WINDOW expected live window, got: ~S" w))
    (when (eq w (minibuffer-window))
      (error "ELISP:SPLIT-WINDOW cannot split minibuffer window"))
    (let* ((buf (window-buffer w))
           (start (window-start w))
           (new (make-elisp-window :buffer buf :start start))
           (wins (or *windows* nil))
           (pos (or (cl:position w wins :test #'eq) 0)))
      (setf *windows*
            (append (subseq wins 0 (min (1+ pos) (length wins)))
                    (list new)
                    (subseq wins (min (1+ pos) (length wins)))))
      new)))

(cl:defun split-window-internal (window _new-pixel-size side _new-normal)
  "Bring-up subset of the C primitive `split-window-internal' (window list only)."
  (declare (cl:ignore _new-pixel-size _new-normal))
  (let* ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:SPLIT-WINDOW-INTERNAL expected live window, got: ~S" w))
    (when (eq w (minibuffer-window))
      (error "ELISP:SPLIT-WINDOW-INTERNAL cannot split minibuffer window"))
    (let* ((buf (window-buffer w))
           (start (window-start w))
           (new (make-elisp-window :buffer buf :start start))
           (wins (or *windows* nil))
           (pos (or (cl:position w wins :test #'eq) 0))
           (beforep (memq side '(above left))))
      (setf *windows*
            (append (subseq wins 0 (if beforep pos (min (1+ pos) (length wins))))
                    (list new)
                    (subseq wins (if beforep pos (min (1+ pos) (length wins))))))
      new)))

(cl:defun split-window-below (&optional _size window-to-split)
  "Bring-up subset of ELisp `split-window-below' (calls `split-window')."
  (declare (cl:ignore _size))
  (split-window (or window-to-split (selected-window)) nil 'below nil))

(cl:defun split-window-right (&optional _size window-to-split)
  "Bring-up subset of ELisp `split-window-right' (calls `split-window')."
  (declare (cl:ignore _size))
  (split-window (or window-to-split (selected-window)) nil 'right nil))

(cl:defun delete-window (&optional window)
  "Bring-up subset of ELisp `delete-window' (no layout; window list only)."
  (let* ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:DELETE-WINDOW expected live window, got: ~S" w))
    (when (eq w (minibuffer-window))
      (error "ELISP:DELETE-WINDOW cannot delete minibuffer window"))
    (let ((wins (or *windows* nil)))
      (when (<= (length wins) 1)
        (error "ELISP:DELETE-WINDOW cannot delete the sole window"))
      (let* ((pos (cl:position w wins :test #'eq))
             (wins* (cl:remove w wins :test #'eq)))
        (setf *windows* wins*)
        (when (eq w (selected-window))
          (let* ((n (length wins*))
                 (idx (if (and pos (>= pos n)) (max 0 (1- n)) (or pos 0))))
            (select-window (nth idx wins*) 'norecord)))
        nil))))

(cl:defun delete-window-internal (window)
  "Bring-up subset of the C primitive `delete-window-internal' (window list only)."
  (let* ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:DELETE-WINDOW-INTERNAL expected live window, got: ~S" w))
    (when (eq w (minibuffer-window))
      (error "ELISP:DELETE-WINDOW-INTERNAL cannot delete minibuffer window"))
    (let ((wins (or *windows* nil)))
      (when (<= (length wins) 1)
        (error "ELISP:DELETE-WINDOW-INTERNAL cannot delete the sole window"))
      (let* ((pos (cl:position w wins :test #'eq))
             (wins* (cl:remove w wins :test #'eq)))
        (setf *windows* wins*)
        (when (eq w (selected-window))
          (let* ((n (length wins*))
                 (idx (if (and pos (>= pos n)) (max 0 (1- n)) (or pos 0))))
            (select-window (nth idx wins*) 'norecord)))
        nil))))

(cl:defun delete-other-windows-internal (window &optional _root)
  "Bring-up subset of the C primitive `delete-other-windows-internal'."
  (declare (cl:ignore _root))
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:DELETE-OTHER-WINDOWS-INTERNAL expected live window, got: ~S" w))
    (when (eq w (minibuffer-window))
      (error "ELISP:DELETE-OTHER-WINDOWS-INTERNAL cannot keep only the minibuffer window"))
    (setf *windows* (list w))
    (select-window w 'norecord)
    nil))

(cl:defun delete-other-windows (&optional window _interactive)
  "Bring-up subset of ELisp `delete-other-windows' (window list only).

Upstream `lisp/window.el` defines `(delete-other-windows &optional window interactive)`
with an `(interactive \"i\\np\")` spec.  Accept the extra INTERACTIVE argument
for compatibility but ignore it."
  (declare (cl:ignore _interactive))
  (let ((w (or window (selected-window))))
    (unless (window-live-p w)
      (error "ELISP:DELETE-OTHER-WINDOWS expected live window, got: ~S" w))
    (when (eq w (minibuffer-window))
      (error "ELISP:DELETE-OTHER-WINDOWS cannot keep only the minibuffer window"))
    (setf *windows* (list w))
    (select-window w 'norecord)
    nil))

(cl:defun other-window (&optional count _all-frames _interactive)
  "Bring-up subset of ELisp `other-window' (window list only)."
  (declare (cl:ignore _all-frames _interactive))
  (let* ((n (or (and (integerp count) count) 1))
         (wins (or *windows* nil)))
    (when (null wins)
      (return-from other-window (selected-window)))
    (let* ((pos (or (cl:position (selected-window) wins :test #'eq) 0))
           (len (length wins))
           (idx (mod (+ pos n) len))
           (w (nth idx wins)))
      (select-window w 'norecord))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Ensure these show up as commands in `M-x` completions.
  (ignore-errors (function-put 'split-window 'interactive-form '(interactive)))
  (ignore-errors (function-put 'split-window-below 'interactive-form '(interactive)))
  (ignore-errors (function-put 'split-window-right 'interactive-form '(interactive)))
  (ignore-errors (function-put 'delete-window 'interactive-form '(interactive)))
  (ignore-errors (function-put 'delete-other-windows 'interactive-form '(interactive)))
  (ignore-errors (function-put 'other-window 'interactive-form '(interactive)))
  ;; Buffer basics used by the PTY editor gate: `C-x k` prompts for a buffer and
  ;; accepts an empty input as "current buffer" (like upstream defaults).
  (ignore-errors
    (function-put
     'kill-buffer
     'interactive-form
     '(interactive
       (list
        (completing-read
         (string-to-unibyte "Kill buffer: ")
         (mapcar #'buffer-name (buffer-list))
         nil
         t
         nil
         nil
         (buffer-name (current-buffer))
         nil))))))

(cl:defun display-buffer (buffer-or-name &optional _action _frame)
  "Bring-up subset of ELisp `display-buffer' (TTY; minimal window list)."
  (declare (cl:ignore _action _frame))
  (let ((buf (or (get-buffer buffer-or-name)
                 (and (stringp buffer-or-name) (get-buffer-create buffer-or-name))
                 (error "ELISP:DISPLAY-BUFFER invalid buffer: ~S" buffer-or-name))))
    (let* ((wins (or *windows* nil))
           (target
             (or (cl:find-if (lambda (w) (and (window-live-p w) (not (eq w (selected-window))))) wins)
                 (when (or (null wins) (= (length wins) 1))
                   (split-window (selected-window))))))
      (unless (and target (window-live-p target))
        (setf target (selected-window)))
      (set-window-buffer target buf)
      target)))

(defstruct elisp-window-configuration
  (windows nil)
  (selected-index 0))

(cl:defun current-window-configuration ()
  "Bring-up stub for ELisp `current-window-configuration'."
  (let* ((wins (or *windows* nil))
         (sel (selected-window))
         (sel-idx (or (cl:position sel wins :test #'eq) 0))
         (snap
           (mapcar (lambda (w)
                     (list (window-buffer w) (window-start w)))
                   wins)))
    (make-elisp-window-configuration :windows snap :selected-index sel-idx)))

(cl:defun set-window-configuration (config)
  "Bring-up stub for ELisp `set-window-configuration'."
  (unless (elisp-window-configuration-p config)
    (error "ELISP:SET-WINDOW-CONFIGURATION expected window configuration, got: ~S" config))
  (let* ((snap (or (elisp-window-configuration-windows config) nil))
         (need (max 1 (length snap)))
         (wins (or *windows* nil))
         (seed (or (and (consp wins) (car wins)) *single-window*))
         (seed-buf (elisp-window-buffer seed))
         (seed-start (or (elisp-window-start seed) (point-min))))
    (when (null wins)
      (setf wins (list *single-window*)))
    (loop while (< (length wins) need) do
      (setf wins (append wins (list (make-elisp-window :buffer seed-buf :start seed-start)))))
    (setf wins (subseq wins 0 need))
    (setf *windows* wins)

    ;; Apply buffers/starts.
    (loop for w in wins
          for cell in snap do
            (destructuring-bind (buf start) cell
              (when buf
                (setf (elisp-window-buffer w) buf))
              (when start
                (setf (elisp-window-start w) start))))

    (let* ((idx (or (elisp-window-configuration-selected-index config) 0))
           (idx* (max 0 (min idx (1- (length wins))))))
      (select-window (nth idx* wins) 'norecord))
    t))

(cl:defun pop-to-buffer (buffer-or-name &optional _action _norecord)
  "Bring-up stub for ELisp `pop-to-buffer'."
  (declare (cl:ignore _action _norecord))
  (let ((win (display-buffer buffer-or-name)))
    (select-window win)
    (window-buffer win)))

(cl:defvar *clemacs-display-buffer-shim* nil)
(cl:defvar *clemacs-pop-to-buffer-shim* nil)
(cl:defvar *clemacs-pop-to-buffer-same-window-shim* nil)
(cl:defvar *clemacs-switch-to-buffer-shim* nil)
(cl:defvar *clemacs-switch-to-buffer-other-window-shim* nil)

(cl:defvar *clemacs-split-window-shim* nil)
(cl:defvar *clemacs-split-window-internal-shim* nil)
(cl:defvar *clemacs-split-window-below-shim* nil)
(cl:defvar *clemacs-split-window-right-shim* nil)
(cl:defvar *clemacs-delete-window-shim* nil)
(cl:defvar *clemacs-delete-window-internal-shim* nil)
(cl:defvar *clemacs-delete-other-windows-shim* nil)
(cl:defvar *clemacs-delete-other-windows-internal-shim* nil)
(cl:defvar *clemacs-other-window-shim* nil)

(cl:defun pop-to-buffer-same-window (buffer-or-name &optional _action _norecord)
  "Bring-up subset of ELisp `pop-to-buffer-same-window' (single-window)."
  (declare (cl:ignore _action _norecord))
  (switch-to-buffer buffer-or-name))

(cl:defun switch-to-buffer (buffer-or-name &optional _norecord _force-same-window)
  "Bring-up subset of ELisp `switch-to-buffer'."
  (declare (cl:ignore _norecord _force-same-window))
  (let ((w (selected-window)))
    (set-window-buffer w buffer-or-name)
    (window-buffer w)))

(cl:defun switch-to-buffer-other-window (buffer-or-name &optional _norecord)
  "Bring-up subset of ELisp `switch-to-buffer-other-window'."
  (declare (cl:ignore _norecord))
  (let ((w (display-buffer buffer-or-name)))
    (select-window w 'norecord)
    (window-buffer w)))

(eval-when (:load-toplevel :execute)
  (when (null *clemacs-display-buffer-shim*)
    (setf *clemacs-display-buffer-shim* (fdefinition 'display-buffer)))
  (when (null *clemacs-pop-to-buffer-shim*)
    (setf *clemacs-pop-to-buffer-shim* (fdefinition 'pop-to-buffer)))
  (when (null *clemacs-pop-to-buffer-same-window-shim*)
    (setf *clemacs-pop-to-buffer-same-window-shim* (fdefinition 'pop-to-buffer-same-window)))
  (when (null *clemacs-switch-to-buffer-shim*)
    (setf *clemacs-switch-to-buffer-shim* (fdefinition 'switch-to-buffer)))
  (when (null *clemacs-switch-to-buffer-other-window-shim*)
    (setf *clemacs-switch-to-buffer-other-window-shim* (fdefinition 'switch-to-buffer-other-window)))

  (when (null *clemacs-split-window-shim*)
    (setf *clemacs-split-window-shim* (fdefinition 'split-window)))
  (when (null *clemacs-split-window-internal-shim*)
    (setf *clemacs-split-window-internal-shim* (fdefinition 'split-window-internal)))
  (when (null *clemacs-split-window-below-shim*)
    (setf *clemacs-split-window-below-shim* (fdefinition 'split-window-below)))
  (when (null *clemacs-split-window-right-shim*)
    (setf *clemacs-split-window-right-shim* (fdefinition 'split-window-right)))
  (when (null *clemacs-delete-window-shim*)
    (setf *clemacs-delete-window-shim* (fdefinition 'delete-window)))
  (when (null *clemacs-delete-window-internal-shim*)
    (setf *clemacs-delete-window-internal-shim* (fdefinition 'delete-window-internal)))
  (when (null *clemacs-delete-other-windows-shim*)
    (setf *clemacs-delete-other-windows-shim* (fdefinition 'delete-other-windows)))
  (when (null *clemacs-delete-other-windows-internal-shim*)
    (setf *clemacs-delete-other-windows-internal-shim* (fdefinition 'delete-other-windows-internal)))
  (when (null *clemacs-other-window-shim*)
    (setf *clemacs-other-window-shim* (fdefinition 'other-window))))

(cl:defun buffer-size (&optional buffer)
  "Bring-up subset of the C primitive `buffer-size'."
  (let ((buf (or buffer (current-buffer))))
    (unless (elisp-buffer-p buf)
      (error "ELISP:BUFFER-SIZE expected buffer, got: ~S" buffer))
    (let ((saved (current-buffer)))
      (unwind-protect
          (progn
            (set-buffer buf)
            (- (point-max) (point-min)))
        (set-buffer saved)))))

(cl:defun force-mode-line-update (&optional _all)
  "Bring-up stub for ELisp `force-mode-line-update'."
  (declare (cl:ignore _all))
  nil)

(cl:defun redisplay (&optional _force)
  "Bring-up stub for ELisp `redisplay'."
  (declare (cl:ignore _force))
  nil)

(cl:defun float-time (&optional time)
  "Bring-up subset of ELisp `float-time'."
  (cond
   ((null time)
    ;; In Emacs, (float-time) is seconds since the Unix epoch (same basis as
    ;; `current-time' / `format-time-string').
    (float-time (current-time)))
   ((numberp time) (cl:coerce time 'double-float))
   ((and (consp time) (integerp (car time)) (consp (cdr time)) (integerp (cadr time)))
    ;; Emacs time values are typically (HI LO USEC PSEC) where seconds are
    ;; HI*2^16 + LO and the tail are fractional seconds.
    (let* ((hi (cl:coerce (car time) 'double-float))
           (lo (cl:coerce (cadr time) 'double-float))
           (usec (cl:coerce (or (caddr time) 0) 'double-float))
           (psec (cl:coerce (or (cadddr time) 0) 'double-float)))
      (+ (* hi 65536.0d0) lo (/ usec 1000000.0d0) (/ psec 1000000000000.0d0))))
   (t (error "ELISP:FLOAT-TIME unsupported time: ~S" time))))

(cl:defun time-convert (time unit)
  "Bring-up subset of ELisp `time-convert'.

Support the cases needed by upstream `lisp/emacs-lisp/timer.el':
- UNIT = 'list: return (HI LO USEC PSEC)
- UNIT = t: return (TICKS . HZ)"
  (cond
   ((eq unit 'list)
    (cond
     ((null time) (current-time))
     ((and (consp time) (integerp (car time)) (consp (cdr time)) (integerp (cadr time)))
      (list (car time) (cadr time) (or (caddr time) 0) (or (cadddr time) 0)))
     (t
      (let* ((x (float-time time))
             (sec (floor x))
             (frac (- x sec))
             (usec (floor (* frac 1000000.0d0)))
             (hi (floor sec 65536))
             (lo (mod sec 65536)))
        (list hi lo usec 0)))))
   ((eq unit t)
    ;; Represent as integer ticks with a fixed Hz to preserve fractional
    ;; seconds when TIME is a float.
    (let* ((x (float-time time))
           (hz 1000000)
           (ticks (round (* x hz))))
      (cons ticks hz)))
   (t
    (error "ELISP:TIME-CONVERT unsupported unit: ~S" unit))))

(cl:defun time-add (time-a time-b)
  "Bring-up subset of ELisp `time-add'."
  (+ (float-time time-a) (float-time time-b)))

(cl:defun time-subtract (time-a time-b)
  "Bring-up subset of ELisp `time-subtract'."
  (- (float-time time-a) (float-time time-b)))

(cl:defun time-less-p (time-a time-b)
  "Bring-up subset of ELisp `time-less-p'."
  (< (float-time time-a) (float-time time-b)))

(cl:defun %unencodable-char-position--ascii-p (coding-system)
  (and (symbolp coding-system)
       (let ((n (string-downcase (%elisp-string->cl-string (symbol-name coding-system)))))
         (or (string= n "us-ascii")
             (string= n "ascii")))))

(cl:defun %unencodable-char-position--scan (s start end coding-system count)
  (labels ((unencodable-p (ch)
             (cond
              ((%unencodable-char-position--ascii-p coding-system)
               (> (char-code ch) 127))
              (t
               ;; Bring-up default: treat everything as encodable.
               nil))))
    (cond
     ((null count)
      (loop for i from start below end do
        (when (unencodable-p (char s i))
          (return i))
        finally (return nil)))
     ((and (integerp count) (plusp count))
      (let ((out nil)
            (remaining count))
        (loop for i from start below end do
          (when (unencodable-p (char s i))
            (push i out)
            (decf remaining)
            (when (zerop remaining)
              (return))))
        (nreverse out)))
     (t
      (error "ELISP:UNENCODABLE-CHAR-POSITION bad COUNT: ~S" count)))))

(cl:defun unencodable-char-position (start end coding-system &optional count object)
  "Bring-up subset of the C primitive `unencodable-char-position'."
  (let ((obj (or object (current-buffer))))
    (cond
     ((stringp obj)
      (let* ((s (%elisp-string->cl-string obj))
             (len (length s))
             (s0 (or start 0))
             (e0 (or end len)))
        (unless (and (integerp s0) (integerp e0) (<= 0 s0) (<= s0 e0) (<= e0 len))
          (error "ELISP:UNENCODABLE-CHAR-POSITION bad range: ~S..~S (len ~S)" start end len))
        (%unencodable-char-position--scan s s0 e0 coding-system count)))
     ((bufferp obj)
      (let* ((s (elisp-buffer-text obj))
             (len (length s))
             (spos (%pos start))
             (epos (%pos end))
             (pmax (1+ len)))
        (unless (and (integerp spos) (integerp epos) (plusp spos) (<= spos epos) (<= epos pmax))
          (error "ELISP:UNENCODABLE-CHAR-POSITION bad range: ~S..~S" start end))
        (let ((v (%unencodable-char-position--scan s (1- spos) (1- epos) coding-system count)))
          (cond
           ((null count) (and v (1+ v)))
           (t (mapcar #'1+ v))))))
     (t
      (error "ELISP:UNENCODABLE-CHAR-POSITION unsupported OBJECT: ~S" obj)))))

(cl:defvar ls-lisp--time-locale nil)

(cl:defun ls-lisp-format-time (file-attr time-index)
  "Bring-up stub for ELisp `ls-lisp-format-time'."
  (let* ((idx (or time-index 5))
         (time (nth idx file-attr))
         (diff (time-subtract time nil))
         (past-cutoff -15778476)
         (format-time-list
           (or (and (boundp 'ls-lisp-format-time-list) (symbol-value 'ls-lisp-format-time-list))
               '("%b %e %H:%M" "%b %e  %Y")))
         (use-localized
           (and (boundp 'ls-lisp-use-localized-time-format)
                (symbol-value 'ls-lisp-use-localized-time-format))))
    (cl:handler-case
        (let ((locale (or (and (boundp 'system-time-locale) system-time-locale)
                          ls-lisp--time-locale)))
          (when (not locale)
            (let ((vars '("LC_ALL" "LC_TIME" "LANG")))
              (loop while (and vars (not (setf locale (getenv (car vars))))) do
                (setf vars (cdr vars))))
            (setf ls-lisp--time-locale (or locale "C")))
          (when (member locale '("C" "POSIX"))
            (setf locale nil))
          (format-time-string
           (if (and (not (time-less-p diff past-cutoff))
                    (not (time-less-p 0 diff)))
               (if (and locale (not use-localized)) "%m-%d %H:%M" (car format-time-list))
               (if (and locale (not use-localized)) "%Y-%m-%d " (cadr format-time-list)))
           time))
      (cl:error () "Unk  0  0000"))))
