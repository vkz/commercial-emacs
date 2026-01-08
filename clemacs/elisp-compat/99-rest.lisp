(in-package #:elisp)


(cl:defun make-keymap ()
  "Extremely small stub for ELisp `make-keymap'."
  (make-elisp-keymap))

(cl:defun make-sparse-keymap (&optional _name)
  "Extremely small stub for ELisp `make-sparse-keymap'."
  (declare (cl:ignore _name))
  (make-elisp-keymap))

(cl:defvar ctl-x-r-map (make-sparse-keymap))

(cl:defvar abbrev-map (make-sparse-keymap))

(cl:defvar function-key-map (make-sparse-keymap))

(cl:defun make-vector (length init)
  "ELisp-ish MAKE-VECTOR."
  (make-array length :initial-element init))

(cl:defun aset (array idx value)
  "ELisp-ish ASET."
  (setf (aref array idx) value)
  value)

(cl:defun use-global-map (keymap)
  "Extremely small stub for ELisp `use-global-map'."
  (setf *global-map* keymap)
  keymap)

(cl:defun current-global-map ()
  "Extremely small stub for ELisp `current-global-map'."
  *global-map*)

(cl:defun current-local-map ()
  "Bring-up subset of ELisp `current-local-map'."
  (and (boundp 'local-map) (symbol-value 'local-map)))

(cl:defun use-local-map (keymap)
  "Bring-up subset of ELisp `use-local-map'."
  (set 'local-map keymap)
  keymap)

(cl:defvar *window-display-table* nil)

(cl:defun window-display-table (&optional _window)
  "Bring-up stub for ELisp `window-display-table'.

clemacs does not implement windows yet; this returns a single global
window display table."
  (declare (cl:ignore _window))
  *window-display-table*)

(cl:defun set-window-display-table (window display-table)
  "Bring-up stub for ELisp `set-window-display-table'."
  (declare (cl:ignore window))
  (setf *window-display-table* display-table)
  display-table)

(cl:defvar *face-id-by-symbol* (make-hash-table :test 'eq))
(cl:defvar *face-symbols-by-id* (make-hash-table :test 'eql))
(cl:defvar *face-next-id* 0)

(cl:defmacro cl-generic-define-context-rewriter (&rest _args)
  "Bring-up stub for `cl-generic-define-context-rewriter'.

This is used at top-level in `lisp/frame.el` and should not evaluate its
arguments during bring-up."
  (declare (cl:ignore _args))
  nil)

(cl:defmacro cl-generic-define-generalizer (&rest _args)
  "Bring-up stub for `cl-generic-define-generalizer'.

This appears early in `lisp/emacs-lisp/cl-generic.el`; ignore it for bring-up."
  (declare (cl:ignore _args))
  nil)

(cl:defmacro oclosure-define (type-and-slots &rest _rest)
  "Bring-up subset of ELisp `oclosure-define'.

clemacs provides a small SBCL-oriented port of upstream `oclosure.el` under
`clemacs/ported/...`, but that port doesn't include the macro layer used by
`cl-generic.el`.  Provide just enough here to unblock `cl-generic`."
  (declare (cl:ignore _rest))
  (let* ((type (cond
                ((symbolp type-and-slots) type-and-slots)
                ((and (consp type-and-slots) (symbolp (car type-and-slots))) (car type-and-slots))
                (t nil)))
         (slots (and (consp type-and-slots) (cdr type-and-slots))))
    (when (or (null type) (not (null slots)))
      (cl:error "ELISP:OCLOSURE-DEFINE unsupported: ~S" type-and-slots))
    `(progn
       (cl:defclass ,type (oclosure) ()
         #+sbcl (:metaclass sb-mop:funcallable-standard-class))
       ',type)))

(cl:defmacro oclosure-lambda (type-and-slots args &rest body)
  "Bring-up subset of ELisp `oclosure-lambda'."
  (declare (indent 2))
  (let* ((type (cond
                ((symbolp type-and-slots) type-and-slots)
                ((and (consp type-and-slots) (symbolp (car type-and-slots))) (car type-and-slots))
                (t nil))))
    (when (null type)
      (cl:error "ELISP:OCLOSURE-LAMBDA unsupported type: ~S" type-and-slots))
    `(make-instance ',type
                    :oclosure-type ',type
                    :call (lambda ,args ,@body))))

;; `cl-generic.el` refers to `cl--generic-isnot-nnm-p' during bootstrap before
;; its own definition later in the file.  Provide a conservative bring-up stub:
;; assume any call-next-method function is "not the no-next-method sentinel".
(cl:defun cl--generic-isnot-nnm-p (_cnm)
  (declare (cl:ignore _cnm))
  t)

(cl:defun %face-register (face id)
  (unless (symbolp face)
    (error "ELISP:FACE register expects symbol face, got: %S" face))
  (unless (and (integerp id) (<= 0 id))
    (error "ELISP:FACE register expects natnump id, got: %S" id))
  (multiple-value-bind (_existing presentp) (gethash face *face-id-by-symbol*)
    (declare (cl:ignore _existing))
    (unless presentp
      (setf (gethash face *face-id-by-symbol*) id)
      (setf (gethash id *face-symbols-by-id*) face)
      (setf *face-next-id* (max *face-next-id* (1+ id)))))
  id)

(eval-when (:load-toplevel :execute)
  ;; These core face IDs appear stable in upstream Emacs (and are used by
  ;; glyph packing in `disp-table.el`).
  (dolist (pair '((default . 0)
                  (bold . 1)
                  (italic . 2)
                  (bold-italic . 3)
                  (underline . 4)
                  (fixed-pitch . 5)
                  (fixed-pitch-serif . 6)
                  (variable-pitch . 7)
                  (variable-pitch-text . 8)))
    (%face-register (car pair) (cdr pair))))

(cl:defun face-id (face &optional _frame)
  "Bring-up subset of ELisp `face-id'.

Return a numeric face ID for FACE.  clemacs currently uses a global registry
and ignores the FRAME argument."
  (declare (cl:ignore _frame))
  (cond
   ((null face) 0)
   ((integerp face) face)
   ((symbolp face)
    (multiple-value-bind (id presentp) (gethash face *face-id-by-symbol*)
      (if presentp
          id
          (%face-register face *face-next-id*))))
   (t
    (error "ELISP:FACE-ID expects symbol or integer, got: %S" face))))

(cl:defun face-list (&optional _frame)
  "Bring-up subset of ELisp `face-list'.

Return a list of known face symbols.  clemacs currently uses a global registry
and ignores the FRAME argument."
  (declare (cl:ignore _frame))
  (let ((pairs nil))
    (maphash (lambda (id sym) (push (cons id sym) pairs)) *face-symbols-by-id*)
    (mapcar #'cdr (sort pairs #'< :key #'car))))

(cl:defun %map--plist-p (xs)
  "Return non-nil when XS looks like an ELisp plist (bring-up heuristic)."
  (and (listp xs)
       (or (null xs)
           (and (consp xs)
                (not (consp (car xs)))
                (consp (cdr xs))))))

(cl:defun %copy-hash-table (ht)
  (unless (hash-table-p ht)
    (error "ELISP:%COPY-HASH-TABLE expects hash-table, got: %S" (type-of ht)))
  (let ((copy (make-hash-table :test (hash-table-test ht)
                               :size (hash-table-size ht)
                               :rehash-size (hash-table-rehash-size ht)
                               :rehash-threshold (hash-table-rehash-threshold ht))))
    (maphash (lambda (k v) (setf (gethash k copy) v)) ht)
    copy))

(cl:defun map-insert (map key value)
  "Bring-up subset of ELisp `map-insert'.

This is a small helper used early by upstream `ert.el`.  Full generic map
support is provided by `lisp/emacs-lisp/map.el` when loaded."
  (cond
   ((hash-table-p map)
    (let ((copy (%copy-hash-table map)))
      (setf (gethash key copy) value)
      copy))
   ((vectorp map)
    (cond
     ((and (integerp key) (<= 0 key) (< key (length map)))
      (let ((copy (cl:copy-seq map)))
        (setf (aref copy key) value)
        copy))
     ((and (integerp key) (<= 0 key))
      (let* ((newlen (1+ key))
             (copy (make-array newlen :initial-element nil)))
        (dotimes (i (length map))
          (setf (aref copy i) (aref map i)))
        (setf (aref copy key) value)
        copy))
     (t
      (error "ELISP:MAP-INSERT vector key must be a natnump, got: %S" key))))
   ((listp map)
    (if (%map--plist-p map)
        (cons key (cons value map))
        (cons (cons key value) map)))
   (t
    (error "ELISP:MAP-INSERT unsupported map type: %S" (type-of map)))))

(cl:defun backtrace (&optional _output)
  "Bring-up subset of ELisp `backtrace'.

Print a host backtrace to `*standard-output*' and return nil."
  (declare (cl:ignore _output))
  (write-string (backtrace-to-string (backtrace-get-frames)) *standard-output*)
  nil)

(cl:defun kill-emacs (&optional arg)
  "Bring-up subset of ELisp `kill-emacs'.

Exit the hosting process.  ARG, when an integer, is used as the process exit
code."
  (let ((code (if (integerp arg) arg 0)))
    (uiop:quit code)))

(defstruct elisp-timer
  (secs 0)
  (repeat nil)
  (function nil)
  (args nil)
  (cancelled nil))

(cl:defvar *elisp-timers* nil)

(cl:defun run-with-idle-timer (secs repeat function &rest args)
  "Bring-up stub for ELisp `run-with-idle-timer' (no real timers)."
  (let ((t0 (make-elisp-timer :secs secs :repeat repeat :function function :args args)))
    (push t0 *elisp-timers*)
    t0))

(cl:defun cancel-timer (timer)
  "Bring-up stub for ELisp `cancel-timer'."
  (unless (elisp-timer-p timer)
    (error "ELISP:CANCEL-TIMER expected timer, got: ~S" timer))
  (setf (elisp-timer-cancelled timer) t)
  (setf *elisp-timers* (remove timer *elisp-timers* :test #'eq))
  nil)

(cl:defun make-obsolete (&rest _args)
  "Stub for ELisp `make-obsolete'."
  (declare (cl:ignore _args))
  nil)

(cl:defmacro defconst (name value &optional docstring)
  "ELisp-ish DEFCONST (currently just DEFPARAMETER).

If NAME lives in the CL package, ignore the definition."
  (declare (cl:ignore docstring))
  (if (and (symbolp name) (eq (symbol-package name) (find-package "CL")))
      `(progn ',name)
      `(defparameter ,name ,value)))

(defparameter -c-@ 0)

(cl:defmacro with-suppressed-warnings (_spec &body body)
  "Compatibility shim; ignores suppression spec."
  (declare (cl:ignore _spec))
  `(progn ,@body))

(cl:defun set-advertised-calling-convention (&rest _args)
  "Stub for ELisp `set-advertised-calling-convention'."
  (declare (cl:ignore _args))
  nil)

(cl:defun get-advertised-calling-convention (&rest _args)
  "Stub for ELisp `get-advertised-calling-convention'."
  (declare (cl:ignore _args))
  nil)

(cl:defun make-obsolete-variable (&rest _args)
  "Stub for ELisp `make-obsolete-variable'."
  (declare (cl:ignore _args))
  nil)

(cl:defmacro defmacro (name lambda-list &body body)
  "Define a macro without mutating CL package symbols.

If NAME lives in the CL package, ignore the definition (this avoids
trying to redefine CL special operators and other locked symbols while
loading upstream ELisp)."
  (if (and (symbolp name) (eq (symbol-package name) (find-package "CL")))
      `(progn ',name)
      (let* ((doc (and body (stringp (car body)) (car body)))
             (doc* (and doc (if (cl:stringp doc) doc (%elisp-string->cl-string doc))))
             (rest (if doc (cdr body) body)))
        `(cl:defmacro ,name ,lambda-list
           ,@(when doc* (list doc*))
           ,@rest))))

(cl:defmacro defun (name lambda-list &body body)
  "Define a function without mutating CL package symbols.

If NAME lives in the CL package, ignore the definition (this avoids
trying to redefine locked symbols while loading upstream ELisp)."
  (if (and (symbolp name) (eq (symbol-package name) (find-package "CL")))
      `(progn ',name)
      (let* ((doc (and body (stringp (car body)) (car body)))
             (doc* (and doc (if (cl:stringp doc) doc (%elisp-string->cl-string doc))))
             (rest (if doc (cdr body) body)))
        `(progn
           ;; Populate `current-load-list' so `load-history' + `symbol-file'
           ;; can report the defining file for TYPE = 'defun.
           (when (and (boundp 'current-load-list) (listp current-load-list))
             (push (cons 'defun ',name) current-load-list))
           (cl:defun ,name ,lambda-list
             ,@(when doc* (list doc*))
             ,@rest)))))

(cl:defmacro defsubst (name lambda-list &body body)
  "ELisp-ish DEFSUBST (currently just DEFUN)."
  `(defun ,name ,lambda-list ,@body))

(cl:defun equal (a b)
  (cond
   ((and (stringp a) (stringp b))
    (cl:string= (string-to-multibyte a) (string-to-multibyte b)))
   ((and (consp a) (consp b))
    (and (equal (car a) (car b))
         (equal (cdr a) (cdr b))))
   ((and (typep a 'elisp-keymap) (typep b 'elisp-keymap))
    (labels ((ht-equal (ha hb)
               (and (= (hash-table-count ha) (hash-table-count hb))
                    (block ok
                      (maphash
                       (lambda (k va)
                         (multiple-value-bind (vb presentp) (gethash k hb)
                           (unless (and presentp (equal va vb))
                             (return-from ok nil))))
                       ha)
                      t))))
      (and (ht-equal (elisp-keymap-table a) (elisp-keymap-table b))
           (equal (elisp-keymap-parent a) (elisp-keymap-parent b)))))
   ((and (vectorp a) (vectorp b))
    (and (= (length a) (length b))
         (loop for i from 0 below (length a)
               always (equal (aref a i) (aref b i)))))
   (t (cl:equal a b))))

(cl:defun type-of (object)
  "ELisp-ish `type-of'.

This deliberately returns coarse ELisp-style type names, not CL's
implementation-specific ones."
  (cond
   ((null object) 'symbol)
   ((symbolp object) 'symbol)
   ((typep object 'clemacs--builtin-class) 'built-in-class)
   ((consp object) 'cons)
   ((integerp object) 'integer)
   ((stringp object) 'string)
   ((vectorp object) 'vector)
   ((hash-table-p object) 'hash-table)
   ((typep object 'elisp-char-table) 'char-table)
   (t (cl:type-of object))))

(cl:defun char-table-p (object)
  "Return non-nil if OBJECT is a char-table."
  (typep object 'elisp-char-table))

(cl:defun make-char-table (type &optional init)
  "Return a new char-table.

This is a minimal bring-up implementation: it supports a fixed range of
character codes (0..65535), a parent link, and extra slots."
  (%make-elisp-char-table type init
                          (make-array +char-table-size+ :initial-element nil)
                          (make-array 0 :adjustable t :fill-pointer 0)
                          nil))

(cl:defun make-translation-table-from-alist (alist)
  "Bring-up subset of ELisp `make-translation-table-from-alist'.

ALIST is an alist of (FROM . TO) entries.  For bring-up we support the common
case where FROM is a single character code and TO is a character code, a
vector of character codes, or nil."
  (let* ((table (make-char-table 'translation-table))
         (rev-table (make-char-table 'translation-table)))
    (dolist (elt alist)
      (let* ((from (car elt))
             (to (cdr elt))
             (from*
               (cond
                ((null from) nil)
                ((characterp from) (if (cl:characterp from) (char-code from) from))
                ((and (vectorp from) (plusp (length from))) (aref from 0))
                (t nil))))
        (when (and from* (integerp from*) (<= 0 from*) (< from* +char-table-size+))
          (setf (aref table from*) to))
        (when (and to (integerp to) (<= 0 to) (< to +char-table-size+))
          (setf (aref rev-table to) from*))))
    (set-char-table-extra-slot table 0 rev-table)
    (set-char-table-extra-slot table 1 1)
    (set-char-table-extra-slot rev-table 1 1)
    table))

(cl:defvar char-script-table (make-char-table 'char-script nil))

(cl:defun set-char-table-parent (table parent)
  "Set TABLE's parent to PARENT and return PARENT."
  (unless (char-table-p table)
    (error "ELISP:set-char-table-parent expects a char-table, got: ~S" table))
  (unless (or (null parent) (char-table-p parent))
    (error "ELISP:set-char-table-parent expects nil or char-table parent, got: ~S"
           parent))
  (setf (elisp-char-table-parent table) parent)
  parent)

(cl:defun char-table-parent (table)
  "Return TABLE's parent, or nil."
  (unless (char-table-p table)
    (error "ELISP:char-table-parent expects a char-table, got: ~S" table))
  (elisp-char-table-parent table))

(cl:defun set-char-table-extra-slot (table n value)
  "Set TABLE's extra slot N to VALUE and return VALUE."
  (unless (char-table-p table)
    (error "ELISP:set-char-table-extra-slot expects a char-table, got: ~S" table))
  (unless (and (integerp n) (<= 0 n))
    (error "ELISP:set-char-table-extra-slot expects non-negative slot index, got: ~S"
           n))
  (let ((extra (elisp-char-table-extra table)))
    (when (<= (length extra) n)
      (adjust-array extra (1+ n) :initial-element nil :fill-pointer (1+ n)))
    (setf (aref extra n) value))
  value)

(cl:defun char-table-extra-slot (table n)
  "Return TABLE's extra slot N."
  (unless (char-table-p table)
    (error "ELISP:char-table-extra-slot expects a char-table, got: ~S" table))
  (unless (and (integerp n) (<= 0 n))
    (error "ELISP:char-table-extra-slot expects non-negative slot index, got: ~S"
           n))
  (let ((extra (elisp-char-table-extra table)))
    (if (< n (length extra)) (aref extra n) nil)))

(cl:defvar *standard-syntax-table* nil)

(cl:defun standard-syntax-table ()
  "Return the global standard syntax table."
  (or *standard-syntax-table*
      (setf *standard-syntax-table* (make-char-table 'syntax-table (cons 0 nil)))))

(cl:defun %syntax-spec-code (spec)
  ;; Mirror Emacs's `syntax_spec_code` mapping for the subset we need during
  ;; early editor-core bring-up.
  (case spec
    (32 0)   ; space
    (46 1)   ; .
    (119 2)  ; w
    (95 3)   ; _
    (40 4)   ; (
    (41 5)   ; )
    (39 6)   ; '
    (34 7)   ; "
    (36 8)   ; $
    (92 9)   ; \
    (47 10)  ; /
    (60 11)  ; <
    (62 12)  ; >
    (64 13)  ; @
    (33 14)  ; !
    (124 15) ; |
    (t nil)))

(cl:defun %syntax-code-spec (code)
  (case code
    (0 32)   ; space
    (1 46)   ; .
    (2 119)  ; w
    (3 95)   ; _
    (4 40)   ; (
    (5 41)   ; )
    (6 39)   ; '
    (7 34)   ; "
    (8 36)   ; $
    (9 92)   ; \
    (10 47)  ; /
    (11 60)  ; <
    (12 62)  ; >
    (13 64)  ; @
    (14 33)  ; !
    (15 124) ; |
    (t 32)))

(cl:defun char-syntax (ch &optional syntax-table)
  "Bring-up subset of ELisp `char-syntax'."
  (let* ((code (cond
                ((integerp ch) ch)
                ((characterp ch) (char-code ch))
                (t (error "ELISP:CHAR-SYNTAX expects a character code, got: ~S" ch))))
         (tab (or syntax-table (syntax-table) (standard-syntax-table))))
    (cond
     ((eq tab :emacs-lisp-mode-syntax-table)
      (if (%syntax-w_-p (code-char code)) 119 32))
     ((char-table-p tab)
      (let* ((entry (aref tab code))
             (raw (if entry (car entry) 0))
             (class (logand raw 255)))
        (%syntax-code-spec class)))
     (t
      (error "ELISP:CHAR-SYNTAX expects a syntax-table char-table, got: ~S" tab)))))

(defconstant +syntax-flag-prefix+ (ash 1 20))

(cl:defun %syntax-entry-from-spec (syntax)
  (unless (or (unibyte-string-p syntax) (cl:stringp syntax))
    (error "ELISP:modify-syntax-entry expects syntax string, got: ~S" syntax))
  (when (zerop (length syntax))
    (error "ELISP:modify-syntax-entry expects non-empty syntax string"))
  (let* ((spec (aref syntax 0))
         (code (%syntax-spec-code spec)))
    (unless (and code (<= 0 code))
      (error "ELISP:unsupported syntax spec code: ~S" spec))
    (let ((flags 0)
          (matching nil))
      (when (and (or (= code 4) (= code 5)) (>= (length syntax) 2))
        (setf matching (aref syntax 1)))
      (loop for i from 1 below (length syntax) do
        (when (= (aref syntax i) 112) ; "p"
          (setf flags (logior flags +syntax-flag-prefix+))))
      (cons (logior code flags) matching))))

(cl:defun modify-syntax-entry (ch syntax &optional table)
  "Set the syntax entry for CH in TABLE according to SYNTAX.

This is a bring-up subset: it supports the common syntax class letters and
the prefix flag (\"p\")."
  (let* ((code (cond
                ((integerp ch) ch)
                ((characterp ch) (char-code ch))
                (t (error "ELISP:modify-syntax-entry expects character code, got: ~S"
                          ch))))
         (tab (or table (error "ELISP:modify-syntax-entry requires TABLE for now")))
         (entry (%syntax-entry-from-spec syntax)))
    (unless (char-table-p tab)
      (error "ELISP:modify-syntax-entry expects a char-table, got: ~S" tab))
    (%char-table-set tab code entry)
    nil))

(cl:defun %lexical-variable-p (symbol env)
  (multiple-value-bind (kind)
      (sb-cltl2:variable-information symbol env)
    (eq kind :lexical)))

(defvar *elisp-variable-aliases* (cl:make-hash-table :test 'eq))

(cl:defvar *buffer-local-variables* (cl:make-hash-table :test 'eq))
(cl:defparameter +elisp-unbound+ (cl:gensym "ELISP-UNBOUND-"))
(cl:defvar *elisp-default-values* (cl:make-hash-table :test 'eq))

(cl:defun %ensure-default-value (symbol)
  (multiple-value-bind (v presentp)
      (gethash symbol *elisp-default-values*)
    (if presentp
        v
        (setf (gethash symbol *elisp-default-values*)
              (handler-case (cl:symbol-value symbol)
                (cl:unbound-variable () +elisp-unbound+))))))

(cl:defun %default-value-or-nil (symbol)
  (let ((v (%ensure-default-value symbol)))
    (if (eq v +elisp-unbound+) nil v)))

(cl:defun %resolve-variable-alias (symbol &key (max-hops 16))
  (loop with cur = symbol
        for hop from 0 below max-hops do
          (multiple-value-bind (next presentp)
              (gethash cur *elisp-variable-aliases*)
            (cond
             ((not presentp) (return cur))
             ((not (symbolp next)) (return cur))
             (t (setf cur next))))
        finally
          (return symbol)))

(cl:defun symbol-value (symbol)
  "ELisp-ish SYMBOL-VALUE (respects `defvaralias')."
  (let* ((sym (%resolve-variable-alias symbol)))
    (when (and (boundp '*current-buffer*)
               (elisp-buffer-p *current-buffer*))
      (multiple-value-bind (v presentp)
          (gethash sym (elisp-buffer-locals *current-buffer*))
        (when presentp
          (return-from symbol-value v))))
    (multiple-value-bind (default presentp)
        (gethash sym *elisp-default-values*)
      (cond
       ((and presentp (not (eq default +elisp-unbound+))) default)
       ((and presentp (eq default +elisp-unbound+))
        (signal 'void-variable (list sym)))
       (t
        (cl:symbol-value sym))))))

(cl:defun set (symbol value)
  "ELisp-ish SET (respects `defvaralias')."
  (let* ((sym (%resolve-variable-alias symbol)))
    (when (and (boundp '*current-buffer*)
               (elisp-buffer-p *current-buffer*))
      (let ((locals (elisp-buffer-locals *current-buffer*)))
        ;; If SYM is buffer-local by default, ensure we write a local binding.
        (when (and (boundp '*buffer-local-variables*)
                   (gethash sym *buffer-local-variables*))
          ;; Capture the default before we start writing buffer-local values
          ;; through CL's symbol-value cell.
          (%ensure-default-value sym)
          (unless (nth-value 1 (gethash sym locals))
            (setf (gethash sym locals)
                  (%default-value-or-nil sym))))
        (multiple-value-bind (_v presentp)
            (gethash sym locals)
          (declare (cl:ignore _v))
          (when presentp
            (setf (gethash sym locals) value)
            ;; Most ELisp code reads variables via bare symbol evaluation, which
            ;; in our bring-up model uses CL's symbol-value cell.  Write-through
            ;; so buffer-local variables are visible to that path (e.g. ERT
            ;; results buffer locals set via `setq-local').
            (setf (cl:symbol-value sym) value)
            (return-from set value)))))
    (setf (cl:symbol-value sym) value)
    ;; If we've captured a default value for this symbol (i.e. it has been
    ;; involved in buffer-local machinery), update that default on global SET.
    (multiple-value-bind (_v presentp)
        (gethash sym *elisp-default-values*)
      (declare (cl:ignore _v))
      (when presentp
        (setf (gethash sym *elisp-default-values*) value)))
    value))

(cl:defun defvaralias (new-alias base-variable &optional _docstring)
  "ELisp-ish DEFVARALIAS."
  (declare (cl:ignore _docstring))
  (setf (gethash new-alias *elisp-variable-aliases*) base-variable)
  new-alias)

(cl:defun define-obsolete-variable-alias (obsolete-name current-name &optional _since)
  "Stub for ELisp `define-obsolete-variable-alias'."
  (declare (cl:ignore _since))
  (defvaralias obsolete-name current-name)
  obsolete-name)

(cl:defun define-obsolete-function-alias (obsolete-name current-definition &optional _since _docstring)
  "Stub for ELisp `define-obsolete-function-alias'."
  (declare (cl:ignore _since _docstring))
  (defalias obsolete-name current-definition)
  obsolete-name)

(cl:defun autoload (function file &optional _docstring _interactive type)
  "Bring-up subset of ELisp `autoload'.

If TYPE is non-nil, treat FUNCTION as a macro (i.e. set its macro-function).
If FUNCTION is already defined, do not overwrite it.

For undefined symbols, install an autoload marker in its function cell."
  (declare (cl:ignore _docstring _interactive))
  (unless (symbolp function)
    (error "ELISP:AUTOLOAD expects a function symbol, got: ~S" function))
  (when (and (symbolp function)
             (eq (symbol-package function) (find-package "CL")))
    ;; Avoid mutating CL package symbols while loading upstream ELisp.
    (return-from autoload function))
  (cond
   (type
    ;; Macro autoload.
    (when (macro-function function)
      (return-from autoload function))
    (let ((tramp nil))
      (setf tramp
              (lambda (form env)
                (declare (cl:ignore env))
                ;; Best-effort: load the library (via `load-path') and retry.
                (load file t)
                (let ((mf (macro-function function)))
                  (when (or (null mf) (eq mf tramp))
                    (error "ELISP:AUTOLOAD failed to load macro %S from %S"
                           function file))
                  (funcall mf form env))))
      (setf (macro-function function) tramp)
      function))
   (t
    ;; Function autoload.
	    (when (fboundp function)
	      (return-from autoload function))
	    (fset function (list 'autoload file))
	    function)))

(cl:defun autoload-do-load (autoload &optional name _macro-only)
  "Bring-up subset of ELisp `autoload-do-load'.

If AUTOLOAD looks like one of our bring-up autoload markers (a list whose CAR is
`autoload'), try to load its referenced FILE and return the updated definition
for NAME when provided.  Otherwise, return AUTOLOAD unchanged."
  (declare (cl:ignore _macro-only))
  (cond
   ((and (consp autoload) (eq (car autoload) 'autoload) (consp (cdr autoload)))
    (let ((file (cadr autoload)))
      (when file
        (load file t))
      (if (and name (symbolp name))
          (symbol-function name)
          autoload)))
   (t autoload)))

(cl:defun custom-autoload (symbol file &optional _interactive)
  "Bring-up stub for ELisp `custom-autoload'.

Used by `ldefs-boot.el` / `loaddefs.el` to register Customize variables and
functions.  For now, delegate to `autoload` and return SYMBOL."
  (declare (cl:ignore _interactive))
  (autoload symbol file)
  symbol)

(cl:defun custom-add-load (_symbol _file)
  "Bring-up stub for ELisp `custom-add-load'.

Used by `loaddefs.el` to record Customize load dependencies."
  (declare (cl:ignore _symbol _file))
  nil)

(cl:defun custom-add-option (_hook _function &rest _args)
  "Bring-up stub for ELisp `custom-add-option'."
  (declare (cl:ignore _hook _function _args))
  nil)

(cl:defun symbol-file (symbol &optional type)
  "Bring-up subset of ELisp `symbol-file'.

For bring-up, we only support TYPE = `ert--test', using the test object's
recorded `file-name' slot (when available)."
  (cond
   ((and (symbolp symbol) (eq type 'ert--test))
    (let ((test (get symbol 'ert--test)))
      (cond
       ((and test (fboundp 'ert-test-file-name))
        (ignore-errors (ert-test-file-name test)))
       (t nil))))
   (t nil)))

(cl:defmacro with-demoted-errors (_format &rest body)
  "Bring-up subset of ELisp `with-demoted-errors'.

Evaluate BODY, but if an error is signaled, demote it and return nil."
  (declare (cl:ignore _format))
  (let ((err (gensym "ERR")))
    `(condition-case ,err
         (progn ,@body)
       (error nil))))

(cl:defun make-variable-buffer-local (variable)
  "Bring-up subset of ELisp `make-variable-buffer-local'."
  (unless (symbolp variable)
    (error "ELISP:MAKE-VARIABLE-BUFFER-LOCAL expects a symbol, got: ~S" variable))
  (let ((sym (%resolve-variable-alias variable)))
    (%ensure-default-value sym)
    (setf (gethash sym *buffer-local-variables*) t))
  variable)

;; Emacs treats the current buffer's local keymap as buffer-local state.
(make-variable-buffer-local 'local-map)
(make-variable-buffer-local 'font-lock-mode)
(make-variable-buffer-local 'font-lock-function)
(make-variable-buffer-local 'default-directory)

(cl:defun make-local-variable (variable)
  "Bring-up subset of ELisp `make-local-variable'.

Creates a buffer-local binding in the current buffer, initialized to the
variable's default/global value."
  (unless (symbolp variable)
    (error "ELISP:MAKE-LOCAL-VARIABLE expects a symbol, got: ~S" variable))
  (unless (and (boundp '*current-buffer*) (elisp-buffer-p *current-buffer*))
    (error "ELISP:MAKE-LOCAL-VARIABLE requires a current buffer"))
  (let* ((sym (%resolve-variable-alias variable))
         (locals (elisp-buffer-locals *current-buffer*)))
    (%ensure-default-value sym)
    (unless (nth-value 1 (gethash sym locals))
      (setf (gethash sym locals)
            (%default-value-or-nil sym))))
  variable)

(cl:defun default-boundp (symbol)
  "Stub for ELisp `default-boundp'.

The \"default\" value is CL's global binding model."
  (let ((sym (%resolve-variable-alias symbol)))
    (multiple-value-bind (v presentp)
        (gethash sym *elisp-default-values*)
      (cond
       ((and presentp (not (eq v +elisp-unbound+))) t)
       ((and presentp (eq v +elisp-unbound+)) nil)
       (t (cl:boundp sym))))))

(cl:defun local-variable-if-set-p (_symbol &optional _buffer)
  "Bring-up subset of ELisp `local-variable-if-set-p'."
  (let* ((symbol (%resolve-variable-alias _symbol))
         (buf (or _buffer *current-buffer*)))
    (cond
     ((null buf) nil)
     ((not (elisp-buffer-p buf)) nil)
     (t (nth-value 1 (gethash symbol (elisp-buffer-locals buf)))))))

(cl:defun local-variable-p (symbol &optional buffer)
  "Bring-up subset of the C primitive `local-variable-p'."
  (unless (symbolp symbol)
    (error "ELISP:LOCAL-VARIABLE-P expects a symbol, got: ~S" symbol))
  (let* ((sym (%resolve-variable-alias symbol))
         (buf (or buffer *current-buffer*)))
    (unless (elisp-buffer-p buf)
      (return-from local-variable-p nil))
    (nth-value 1 (gethash sym (elisp-buffer-locals buf)))))

(cl:defun buffer-local-value (symbol buffer)
  "Bring-up subset of the C primitive `buffer-local-value'."
  (unless (symbolp symbol)
    (error "ELISP:BUFFER-LOCAL-VALUE expects symbol, got: ~S" symbol))
  (let* ((sym (%resolve-variable-alias symbol))
         (buf (or buffer *current-buffer*)))
    (unless (elisp-buffer-p buf)
      (error "ELISP:BUFFER-LOCAL-VALUE expects buffer, got: ~S" buffer))
    (multiple-value-bind (v presentp)
        (gethash sym (elisp-buffer-locals buf))
      (if presentp
          v
          (multiple-value-bind (d dpresentp)
              (gethash sym *elisp-default-values*)
            (cond
             ((and dpresentp (not (eq d +elisp-unbound+))) d)
             ((and dpresentp (eq d +elisp-unbound+))
              (signal 'void-variable (list sym)))
             (t
              (cl:symbol-value sym))))))))

(cl:defun kill-local-variable (variable)
  "Bring-up subset of the C primitive `kill-local-variable'."
  (unless (symbolp variable)
    (error "ELISP:KILL-LOCAL-VARIABLE expects a symbol, got: ~S" variable))
  (unless (and (boundp '*current-buffer*) (elisp-buffer-p *current-buffer*))
    (error "ELISP:KILL-LOCAL-VARIABLE requires a current buffer"))
  (let* ((sym (%resolve-variable-alias variable))
         (locals (elisp-buffer-locals *current-buffer*)))
    (remhash sym locals)
    (multiple-value-bind (d presentp)
        (gethash sym *elisp-default-values*)
      (cond
       ((and presentp (not (eq d +elisp-unbound+)))
        (setf (cl:symbol-value sym) d))
       ((and presentp (eq d +elisp-unbound+))
        (cl:makunbound sym))
       (t nil))))
  variable)

(cl:defun default-value (symbol)
  "Stub for ELisp `default-value'."
  (let ((sym (%resolve-variable-alias symbol)))
    (multiple-value-bind (v presentp)
        (gethash sym *elisp-default-values*)
      (cond
       ((and presentp (not (eq v +elisp-unbound+))) v)
       ((and presentp (eq v +elisp-unbound+))
        (signal 'void-variable (list sym)))
       (t (cl:symbol-value sym))))))

(cl:defun set-default (symbol value)
  "Stub for ELisp `set-default'."
  (let ((sym (%resolve-variable-alias symbol)))
    (setf (gethash sym *elisp-default-values*) value)
    (let ((buf (and (boundp '*current-buffer*) *current-buffer*)))
      (when (and buf (elisp-buffer-p buf))
        (let ((locals (elisp-buffer-locals buf)))
          (when (nth-value 1 (gethash sym locals))
            (return-from set-default value)))))
    (setf (cl:symbol-value sym) value)
    value))

(cl:defmacro setq (&environment env &rest pairs)
  (unless (evenp (length pairs))
    (error "ELISP:SETQ expects an even number of arguments"))

  (let ((forms nil))
    (loop for (var val) on pairs by (cl:function cl:cddr) do
      (unless (symbolp var)
        (error "ELISP:SETQ only supports symbol variables, got: ~S" var))
      (push (if (%lexical-variable-p var env)
                `(cl:setq ,var ,val)
                `(set ',var ,val))
            forms))
    `(progn ,@(nreverse forms))))

(cl:defmacro define-minor-mode (name &rest args)
  "Bring-up stub for ELisp `define-minor-mode'.

This only defines the mode variable and a basic toggling function."
  (unless (symbolp name)
    (error "ELISP:DEFINE-MINOR-MODE expects a symbol name, got: ~S" name))
  (let ((doc (and args (stringp (car args)) (pop args))))
    `(progn
       (defvar ,name nil ,doc)
       (defun ,name (&optional arg)
         ,@(when doc (list doc))
         (setq ,name (cond
                      ((null arg) (not ,name))
                      ((integerp arg) (> arg 0))
                      (t arg)))
         ,name))))

(cl:defun fset (symbol definition)
  "Set SYMBOL's function cell to DEFINITION.

Also installs a CL-visible definition when needed so that evaluating ELisp as
CL forms (e.g. calls like (foo ...)) works during bootstrap."
  (when (and (symbolp symbol)
             (eq (symbol-package symbol) (find-package "CL")))
    (return-from fset symbol))
  (when (null definition)
    (remhash symbol *elisp-function-cells*)
    (when (symbolp symbol)
      (ignore-errors (setf (cl:macro-function symbol) nil))
      (when (cl:fboundp symbol)
        (ignore-errors (cl:fmakunbound symbol))))
    (return-from fset symbol))
  (setf (gethash symbol *elisp-function-cells*) definition)
  (when (symbolp symbol)
    (cond
     ((and (consp definition) (eq (car definition) 'macro) (cl:functionp (cdr definition)))
      (setf (cl:macro-function symbol) (cdr definition)))
     ((cl:functionp definition)
      (setf (cl:fdefinition symbol) definition))
     (t
      (setf (cl:fdefinition symbol)
            (lambda (&rest args)
              (cl:apply (%resolve-function symbol) args))))))
  symbol)

(cl:defun defalias (symbol definition &optional _docstring)
  "Alias SYMBOL's function definition to DEFINITION."
  (declare (cl:ignore _docstring))
  (when (and (symbolp symbol)
             (eq (symbol-package symbol) (find-package "CL")))
    (return-from defalias symbol))
  (fset symbol definition))

(cl:defmacro while (test &body body)
  "ELisp-ish WHILE."
  `(loop while ,test do (progn ,@body)))

(cl:defun plist-get (plist prop)
  (getf plist prop))

(cl:defun plist-put (plist prop value)
  (let ((p plist))
    (setf (getf p prop) value)
    p))

(cl:defun plist-member (plist prop)
  "Bring-up subset of ELisp `plist-member'."
  (let ((p plist))
    (loop while (consp p) do
      (when (eq (car p) prop)
        (return p))
      (setf p (cddr p))
      finally (return nil))))

(cl:defun setcdr (cell newcdr)
  "ELisp-ish SETCDR."
  (unless (consp cell)
    (error "ELISP:SETCDR expected cons, got: ~S" cell))
  (setf (cdr cell) newcdr)
  newcdr)

(cl:defun setcar (cell newcar)
  "ELisp-ish SETCAR."
  (unless (consp cell)
    (error "ELISP:SETCAR expected cons, got: ~S" cell))
  (setf (car cell) newcar)
  newcar)

(cl:defun car-safe (x)
  "ELisp-ish CAR-SAFE."
  (if (consp x) (car x) nil))

(cl:defun cdr-safe (x)
  "ELisp-ish CDR-SAFE."
  (if (consp x) (cdr x) nil))

(cl:defun assq (key alist)
  "ELisp-ish ASSQ."
  (dolist (cell alist nil)
    (when (and (consp cell) (eq (car cell) key))
      (return cell))))

(cl:defun assoc (key alist &optional testfn)
  "ELisp-ish ASSOC."
  (let ((test (or testfn #'equal)))
    (dolist (cell alist nil)
      (when (and (consp cell) (funcall test key (car cell)))
        (return cell)))))

(cl:defun rassq (value alist)
  "ELisp-ish RASSQ."
  (dolist (cell alist nil)
    (when (and (consp cell) (eq (cdr cell) value))
      (return cell))))

(cl:defun rassoc (value alist)
  "ELisp-ish RASSOC (equal-based)."
  (dolist (cell alist nil)
    (when (and (consp cell) (equal (cdr cell) value))
      (return cell))))

(cl:defun alist-get (key alist &optional default _remove testfn)
  "Bring-up subset of ELisp `alist-get'."
  (declare (cl:ignore _remove))
  (let ((test (or testfn #'equal)))
    (dolist (cell alist default)
      (when (and (consp cell) (funcall test key (car cell)))
        (return (cdr cell))))))

(cl:define-setf-expander alist-get (key alist &optional default remove testfn &environment env)
  (multiple-value-bind (alist-temps alist-vals alist-store-vars alist-store-form alist-access)
      (cl:get-setf-expansion alist env)
	    (let ((k (gensym "KEY"))
	          (d (gensym "DEFAULT"))
	          (r (gensym "REMOVE"))
	          (tf (gensym "TESTFN"))
	          (new (gensym "NEW"))
	          (alist-var (gensym "ALIST"))
	          (prev-tail (gensym "PREV-TAIL"))
	          (found-tail (gensym "FOUND-TAIL"))
	          (test (gensym "TEST")))
	      (cl:values
	       (append alist-temps (list k d r tf))
	       (append alist-vals (list key default remove testfn))
	       (list new)
	       `(let* ((,alist-var ,alist-access)
               (,test (or ,tf #'equal))
               (,prev-tail nil)
               (,found-tail nil))
          (let ((tail ,alist-var)
                (prev nil))
            (loop while (consp tail) do
              (let ((cell (car tail)))
                (when (and (consp cell) (funcall ,test ,k (car cell)))
                  (setf ,found-tail tail)
                  (setf ,prev-tail prev)
                  (return)))
              (setf prev tail)
              (setf tail (cdr tail))))
          (cond
           ((and ,r (equal ,new ,d))
            (when ,found-tail
              (if (null ,prev-tail)
                  (setf ,alist-var (cdr ,found-tail))
                  (setf (cdr ,prev-tail) (cdr ,found-tail)))))
           (,found-tail
            (setf (cdr (car ,found-tail)) ,new))
           (t
            (setf ,alist-var (cons (cons ,k ,new) ,alist-var))))
          (let (,@(loop for sv in alist-store-vars collect `(,sv ,alist-var)))
            ,alist-store-form)
          ,new)
       `(alist-get ,k ,alist-access ,d ,r ,tf)))))

(cl:defun memq (elt list)
  "ELisp-ish MEMQ."
  (loop for tail on list
        when (eq elt (car tail)) do (return tail)
        finally (return nil)))

(cl:defun memql (elt list)
  "Bring-up subset of ELisp `memql' (EQL-based member)."
  (loop for tail on list
        when (eql elt (car tail)) do (return tail)
        finally (return nil)))

(cl:defun member (elt list)
  "ELisp-ish MEMBER (equal-based)."
  (loop for tail on list
        when (equal elt (car tail)) do (return tail)
        finally (return nil)))

(cl:defun delq (elt list)
  "ELisp-ish DELQ (destructive eq-based deletion)."
  (labels ((skip-head (xs)
             (loop while (and (consp xs) (eq elt (car xs))) do
               (setf xs (cdr xs)))
             xs))
    (let* ((head (skip-head list))
           (prev head)
           (cur (and (consp head) (cdr head))))
      (loop while (consp cur) do
        (cond
         ((eq elt (car cur))
          (setf (cdr prev) (cdr cur))
          (setf cur (cdr cur)))
         (t
          (setf prev cur)
          (setf cur (cdr cur)))))
      head)))

(cl:defun delete-dups (list)
  "Bring-up subset of ELisp `delete-dups' (destructive equal-based deletion)."
  (labels ((skip-head (xs seen)
             (loop while (and (consp xs) (cl:member (car xs) seen :test #'equal)) do
               (setf xs (cdr xs)))
             xs))
    (let* ((seen nil)
           (head (if (consp list)
                     (progn (push (car list) seen) list)
                     list)))
      (when (not (consp head))
        (return-from delete-dups head))
      (let* ((prev head)
             (cur (cdr head)))
        (loop while (consp cur) do
          (cond
           ((cl:member (car cur) seen :test #'equal)
            (setf (cdr prev) (cdr cur))
            (setf cur (cdr cur)))
           (t
            (push (car cur) seen)
            (setf prev cur)
            (setf cur (cdr cur))))))
      head)))

(cl:defun proper-list-p (x)
  "Bring-up subset of ELisp `proper-list-p'.

Returns the length of X if it is a proper list, otherwise nil."
  (cond
   ((null x) 0)
   ((not (consp x)) nil)
   (t
    (let ((slow x)
          (fast x)
          (len 0))
      (loop
        ;; Step FAST once.
        (cond
         ((null fast) (return len))
         ((not (consp fast)) (return nil))
         (t
          (incf len)
          (setf fast (cdr fast))))
        ;; Cycle check.
        (when (eq fast slow) (return nil))
        ;; Step FAST again; step SLOW once.
        (cond
         ((null fast) (return len))
         ((not (consp fast)) (return nil))
         (t
          (incf len)
          (setf fast (cdr fast))
          (setf slow (cdr slow))))
        (when (eq fast slow) (return nil)))))))

(cl:defun recordp (_x)
  "Bring-up stub for ELisp `recordp'."
  (declare (cl:ignore _x))
  nil)

(eval-when (:load-toplevel :execute)
  ;; Upstream expects `string=' to be an alias for `string-equal' (used by ERT).
  (defalias 'string= 'string-equal))
