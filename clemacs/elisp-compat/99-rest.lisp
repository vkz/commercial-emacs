(in-package #:elisp)


(cl:defun make-keymap (&optional _name)
  "Bring-up subset of ELisp `make-keymap'."
  (declare (cl:ignore _name))
  ;; Return an Emacs-shaped keymap list so libraries that poke at keymap
  ;; internals (e.g. `isearch.el`) can load.  We keep a backing `elisp-keymap'
  ;; object in the 3rd cell for our compatibility `define-key'/`lookup-key'
  ;; implementations.
  (list 'keymap (make-char-table 'keymap nil) (make-elisp-keymap)))

(cl:defun make-sparse-keymap (&optional _name)
  "Bring-up subset of ELisp `make-sparse-keymap'."
  (declare (cl:ignore _name))
  (list 'keymap nil (make-elisp-keymap)))

(cl:defvar special-event-map (make-sparse-keymap)
  "Bring-up default for the C-defined variable `special-event-map'.")

(cl:defmacro defvar-keymap (variable-name &rest defs)
  "Bring-up subset of ELisp `defvar-keymap'.

Supports only:
- `:doc' for the variable docstring
- plain KEY/DEFINITION pairs (no `:menu' support yet)."
  (let ((doc nil)
        (pairs defs))
    (loop while (and pairs (keywordp (car pairs)) (not (eq (car pairs) :menu))) do
      (let ((k (pop pairs)))
        (unless pairs
          (error "ELISP:DEFVAR-KEYMAP missing value for keyword: %S" k))
        (let ((v (pop pairs)))
          (cond
           ((eq k :doc) (setf doc v))
           ((cl:member k '(:full :keymap :parent :suppress :name :prefix :repeat)
                       :test #'eq)
            nil)
           (t
            ;; During bring-up, be permissive: ignore unknown keywords rather
            ;; than hard-failing a checkpointed startup manifest.
            nil)))))
    (when (not (zerop (mod (length pairs) 2)))
      (error "ELISP:DEFVAR-KEYMAP uneven number of key/definition pairs: %S" pairs))
    ;; For now, ignore OPTS and always create a sparse keymap.  This is enough
    ;; to checkpoint `lisp/ldefs-boot.el' and early core libraries that define
    ;; keymaps in their autoloads.
    (let ((map-sym (cl:gensym "KEYMAP-")))
      `(defvar ,variable-name
         (let ((,map-sym (make-sparse-keymap)))
           ,@(loop for (k v) on pairs by #'cddr
                   when (not (eq k :menu))
                     collect `(define-key ,map-sym ,k ,v))
           ,map-sym)
         ,doc)))
  )

(cl:defvar ctl-x-r-map (make-sparse-keymap))

(cl:defvar abbrev-map (make-sparse-keymap))

(cl:defvar function-key-map (make-sparse-keymap))

(cl:defun make-vector (length init)
  "ELisp-ish MAKE-VECTOR."
  (make-array length :initial-element init))

(cl:defun aset (array idx value)
  "ELisp-ish ASET."
  (labels ((bad-index ()
             (signal 'args-out-of-range (list array idx))))
    (cond
     ((unibyte-string-p array)
      (unless (integerp idx)
        (signal 'wrong-type-argument (list 'integerp idx)))
      (unless (integerp value)
        (error "ELISP:ASET expects character code for unibyte string, got: %S" value))
      (unless (and (integerp value) (<= 0 value 255))
        (error "ELISP:ASET unibyte string code out of range: %S" value))
      (handler-case
          (setf (aref array idx) value)
        #+sbcl
        (sb-int:invalid-array-index-error () (bad-index)))
      value)
     ((cl:stringp array)
      (unless (integerp idx)
        (signal 'wrong-type-argument (list 'integerp idx)))
      (unless (integerp value)
        (error "ELISP:ASET expects character code for string, got: %S" value))
      (handler-case
          (setf (char array idx) (%elisp-code->char value))
        #+sbcl
        (sb-int:invalid-array-index-error () (bad-index)))
      value)
     (t
      (unless (integerp idx)
        (signal 'wrong-type-argument (list 'integerp idx)))
      (handler-case
          (setf (aref array idx) value)
        #+sbcl
        (sb-int:invalid-array-index-error () (bad-index)))
      value))))

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

(cl:defun set-buffer-redisplay (&rest _args)
  "Bring-up stub for the C function `set-buffer-redisplay'.

In Emacs this is used as a variable watcher; during clemacs bring-up we treat
it as a no-op redisplay hint."
  (declare (cl:ignore _args))
  nil)

(cl:defvar *variable-watchers*
  (cl:make-hash-table :test 'eq))

(cl:defun get-variable-watchers (variable)
  "Bring-up subset of the C primitive `get-variable-watchers'."
  (unless (symbolp variable)
    (signal 'wrong-type-argument (list 'symbolp variable)))
  (cl:copy-list (gethash variable *variable-watchers*)))

(cl:defun add-variable-watcher (variable watcher)
  "Bring-up subset of the C primitive `add-variable-watcher'."
  (unless (symbolp variable)
    (signal 'wrong-type-argument (list 'symbolp variable)))
  (unless (functionp watcher)
    (signal 'wrong-type-argument (list 'functionp watcher)))
  (let ((watchers (gethash variable *variable-watchers*)))
    (unless (cl:member watcher watchers :test #'eq)
      (setf (gethash variable *variable-watchers*) (cons watcher watchers))))
  nil)

(cl:defun remove-variable-watcher (variable watcher)
  "Bring-up subset of the C primitive `remove-variable-watcher'."
  (unless (symbolp variable)
    (signal 'wrong-type-argument (list 'symbolp variable)))
  (unless (functionp watcher)
    (signal 'wrong-type-argument (list 'functionp watcher)))
  (let* ((watchers (gethash variable *variable-watchers*))
         (new (cl:remove watcher watchers :test #'eq)))
    (cond
     ((null new) (remhash variable *variable-watchers*))
     (t (setf (gethash variable *variable-watchers*) new))))
  nil)

(cl:defvar *oclosure-defined-slots* (cl:make-hash-table :test 'eq))

(cl:defmacro oclosure-define (type-and-options &rest rest)
  "Bring-up subset of ELisp `oclosure-define'.

This provides enough of the macro layer to load `lisp/emacs-lisp/nadvice.el`
and other early startup files that define lightweight oclosure types."
  (let* ((type
          (cond
           ((cl:symbolp type-and-options) type-and-options)
           ((and (cl:consp type-and-options) (cl:symbolp (car type-and-options)))
            (car type-and-options))
           (t nil)))
         (options
          (cond
           ((cl:symbolp type-and-options) nil)
           ((cl:consp type-and-options) (cdr type-and-options))
           (t nil)))
         (doc (and rest (stringp (car rest)) (pop rest)))
         (doc* (and doc (if (cl:stringp doc) doc (%elisp-string->cl-string doc))))
         (slots rest)
         (predicate-name nil)
         (copiers nil))
    (when (null type)
      (cl:error "ELISP:OCLOSURE-DEFINE unsupported: ~S" type-and-options))
    (dolist (opt options)
      (cond
       ((and (cl:consp opt) (cl:eq (car opt) :predicate))
        (setf predicate-name (cadr opt)))
       ((and (cl:consp opt) (cl:eq (car opt) :copier))
        ;; (:copier name (slot...))
        (push (list (cadr opt) (caddr opt)) copiers))
       (t
        (cl:error "ELISP:OCLOSURE-DEFINE unsupported option: ~S" opt))))

    ;; Make slot names available to later `oclosure-lambda` macroexpansion in
    ;; the same compilation unit (notably in `nadvice.el` eval-when-compile).
    (setf (cl:gethash type *oclosure-defined-slots*) slots)

    (let* ((type-name (cl:symbol-name type))
           (type-pkg (or (cl:symbol-package type) (cl:find-package :elisp)))
           (slot-defs
            (mapcar
             (lambda (slot)
               (unless (cl:symbolp slot)
                 (cl:error "ELISP:OCLOSURE-DEFINE slot must be symbol, got: ~S" slot))
               (let* ((kw (cl:intern (cl:symbol-name slot) :keyword))
                      (acc (cl:intern
                            (cl:format nil "~A--~A" type-name (cl:symbol-name slot))
                            type-pkg)))
                 `(,slot :initarg ,kw :initform nil :accessor ,acc)))
             slots))
           (copier-defs
            (mapcar
             (lambda (spec)
               (cl:destructuring-bind (copier-name copier-slots) spec
                 (unless (cl:symbolp copier-name)
                   (cl:error "ELISP:OCLOSURE-DEFINE copier name must be symbol, got: ~S"
                             copier-name))
                 (unless (cl:listp copier-slots)
                   (cl:error "ELISP:OCLOSURE-DEFINE copier slot list must be list, got: ~S"
                             copier-slots))
                 (let* ((args (mapcar (lambda (s)
                                        (unless (cl:symbolp s)
                                          (cl:error "ELISP:OCLOSURE-DEFINE copier slot must be symbol, got: ~S"
                                                    s))
                                        s)
                                      copier-slots))
                        (slot->arg (let ((it (cl:make-hash-table :test 'eq)))
                                     (dolist (s copier-slots)
                                       (setf (cl:gethash s it) s))
                                     it))
                        (initargs
                         (mapcan
                          (lambda (slot)
                            (let* ((kw (cl:intern (cl:symbol-name slot) :keyword))
                                   (acc (cl:intern
                                         (cl:format nil "~A--~A" type-name (cl:symbol-name slot))
                                         type-pkg))
                                   (val (if (cl:gethash slot slot->arg)
                                            slot
                                            `(,acc proto))))
                              (list kw val)))
                          slots)))
                  `(cl:defun ,copier-name (proto ,@args)
                      (make-instance ',type
                                     :oclosure-type ',type
                                     :call (%oclosure-call proto)
                                     ,@initargs)))))
             copiers)))
      `(progn
         (eval-when (:compile-toplevel :load-toplevel :execute)
           (setf (cl:gethash ',type *oclosure-defined-slots*) ',slots))
         (cl:defclass ,type (oclosure)
           ,slot-defs
           #+sbcl (:metaclass sb-mop:funcallable-standard-class)
           ,@(when doc* `((:documentation ,doc*))))
         (eval-when (:load-toplevel :execute)
           (when (and (cl:fboundp 'cl--find-class)
                      (cl:fboundp 'oclosure--class-make)
                      (cl:fboundp 'cl--make-slot-descriptor))
             (cl:labels ((allparents (name parent)
                          (if (and parent (cl:fboundp 'cl--class-allparents))
                              (cons name (cl--class-allparents parent))
                              (list name))))
               (let ((parent (cl:ignore-errors (cl--find-class 'oclosure))))
                 (when parent
                   (let ((slotdescs (cl:make-array ,(cl:length slots) :initial-element nil)))
                     (cl:dotimes (i ,(cl:length slots))
                       (setf (cl:aref slotdescs i)
                             (cl--make-slot-descriptor (cl:nth i ',slots))))
                     (setf (cl--find-class ',type)
                           (oclosure--class-make
                            ',type
                            ,doc*
                            slotdescs
                            (list parent)
                            (allparents ',type parent)))))))))
         ,@(when predicate-name
             `((cl:defun ,predicate-name (obj)
                 (typep obj ',type))))
         ,@copier-defs
         ',type))))

(cl:defmacro oclosure-lambda (type-and-slots args &rest body)
  "Bring-up subset of ELisp `oclosure-lambda'."
  (declare (indent 2))
  (let* ((type (cond
                ((cl:symbolp type-and-slots) type-and-slots)
                ((and (cl:consp type-and-slots) (cl:symbolp (car type-and-slots)))
                 (car type-and-slots))
                (t nil)))
         (inits (and (cl:consp type-and-slots) (cdr type-and-slots))))
    (when (null type)
      (cl:error "ELISP:OCLOSURE-LAMBDA unsupported type: ~S" type-and-slots))
    (let* ((known-slots (cl:gethash type *oclosure-defined-slots*))
           (init-slots (mapcar #'cl:car inits))
           (slot-names (remove-duplicates (append known-slots init-slots) :test #'cl:eq))
           (self (cl:gensym "SELF"))
           (initargs
            (mapcan
             (lambda (pair)
               (unless (and (cl:consp pair) (cl:symbolp (cl:car pair)) (cl:consp (cl:cdr pair))
                            (null (cddr pair)))
                 (cl:error "ELISP:OCLOSURE-LAMBDA bad slot init: ~S" pair))
               (let ((slot (cl:car pair))
                     (value (cadr pair)))
                 (list (cl:intern (cl:symbol-name slot) :keyword) value)))
             inits))
           (slot-bindings
            (mapcar (lambda (slot) `(,slot (cl:slot-value ,self ',slot))) slot-names)))
      `(make-instance ',type
                      :oclosure-type ',type
                      ,@initargs
                      :call (lambda (,self ,@args)
                              (let ,slot-bindings
                                ,@body))))))

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

(cl:defun set-face-documentation (face string)
  "Bring-up subset of ELisp `set-face-documentation'."
  (unless (symbolp face)
    (error "ELISP:SET-FACE-DOCUMENTATION expected symbol face, got: %S" face))
  (unless (documentation-stringp string)
    (error "ELISP:SET-FACE-DOCUMENTATION expected docstring object, got: %S" string))
  (put face 'face-documentation string))

(cl:defun face-spec-set (face spec &optional (spec-type 'face-override-spec))
  "Bring-up stub for ELisp `face-spec-set'."
  (unless (symbolp face)
    (error "ELISP:FACE-SPEC-SET expected symbol face, got: %S" face))
  ;; Ensure the face exists in our minimal registry.
  (ignore-errors (face-id face))
  (put face spec-type spec)
  spec)

(cl:defun internal-set-font-selection-order (_value)
  "TTY-only stub for the C primitive `internal-set-font-selection-order'."
  (declare (cl:ignore _value))
  nil)

(cl:defun internal-set-alternative-font-family-alist (_value)
  "TTY-only stub for the C primitive `internal-set-alternative-font-family-alist'."
  (declare (cl:ignore _value))
  nil)

(cl:defun internal-set-alternative-font-registry-alist (_value)
  "TTY-only stub for the C primitive `internal-set-alternative-font-registry-alist'."
  (declare (cl:ignore _value))
  nil)

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

(cl:defun copy-hash-table (table &optional _copy-keys _copy-values)
  "Bring-up subset of ELisp `copy-hash-table'."
  (declare (cl:ignore _copy-keys _copy-values))
  (%copy-hash-table table))

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

(cl:defun backtrace-frame--internal (_fn _nframes _base)
  "Bring-up stub for `backtrace-frame--internal'.

This is used by `backtrace-frame` (in `lisp/subr.el`) and therefore by some
callers of `called-interactively-p`.  For clemacs bring-up, return nil to
indicate \"no such frame\"."
  (declare (cl:ignore _fn _nframes _base))
  nil)

(cl:defun kill-emacs (&rest args)
  "Bring-up subset of ELisp `kill-emacs'.

Exit the hosting process.  When the first arg is an integer, use it as the
process exit code."
  (let* ((arg (and args (first args)))
         (code (if (integerp arg) arg 0)))
    (if (and (boundp 'noninteractive) (not noninteractive))
        (cl:error 'clemacs:clemacs-quit)
        (uiop:quit code))))

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

(cl:defvar *advertised-calling-conventions* (cl:make-hash-table :test 'eq))

(cl:defun set-advertised-calling-convention (&rest _args)
  "Bring-up subset of ELisp `set-advertised-calling-convention'.

Supports the usage exercised by `map-tests.el' via `cl-defgeneric' declares."
  (declare (cl:ignore _args))
  (destructuring-bind (function arglist &optional _version &rest _rest) _args
    (declare (cl:ignore _version _rest))
    (labels ((function-name-symbol (fn)
               (cond
                ((symbolp fn) fn)
                ;; `symbol-function' can return non-function markers (notably
                ;; autoload placeholders, and our `(macro . FN)` wrapper).
                ;; Treat those as "unknown name" in this helper.
                ((and (consp fn) (eq (car fn) 'autoload)) nil)
                ((and (consp fn) (eq (car fn) 'macro))
                 (function-name-symbol (cdr fn)))
                #+sbcl
                ((typep fn 'cl:generic-function)
                 (let ((nm (sb-mop:generic-function-name fn)))
                   (and (symbolp nm) nm)))
                (t
                 (multiple-value-bind (_lambda _closed name)
                     (cl:function-lambda-expression fn)
                   (declare (cl:ignore _lambda _closed))
                   (and (symbolp name) name))))))
	    (let* ((sym (function-name-symbol function))
	           (fnobj
	             (cond
	              ;; Do not force autoload while registering metadata.
	              ;; `loaddefs.el` calls this on many autoloaded symbols (notably
	              ;; `byte-compile-file`), and Emacs does not load the autoloaded
	              ;; library for this.
	              ((and (symbolp function) (fboundp function))
	               (let ((sf (ignore-errors (symbol-function function))))
	                 (cond
	                  ((and (consp sf) (eq (car sf) 'autoload)) nil)
	                  ((and (consp sf) (eq (car sf) 'macro)) (cdr sf))
	                  ((cl:functionp sf) sf)
	                  #+sbcl
	                  ((typep sf 'sb-mop:funcallable-standard-object) sf)
	                  (t nil))))
	              ((cl:functionp function) function)
	              #+sbcl
	              ((typep function 'sb-mop:funcallable-standard-object) function)
	              (t nil))))
        (when sym
          (function-put sym 'advertised-calling-convention arglist))
        (when fnobj
          (setf (gethash fnobj *advertised-calling-conventions*) arglist))
        arglist))))

(cl:defun get-advertised-calling-convention (&rest _args)
  "Bring-up subset of ELisp `get-advertised-calling-convention'."
  (declare (cl:ignore _args))
  (destructuring-bind (function &optional _argspec &rest _rest) _args
    (declare (cl:ignore _argspec _rest))
    ;; In Emacs, asking about an autoload placeholder returns `t` (not a
    ;; structured arglist), and it must not error (cl-generic calls this during
    ;; method definition/defalias).
    (when (and (consp function) (eq (car function) 'autoload))
      (return-from get-advertised-calling-convention t))
    (labels ((function-name-symbol (fn)
               (cond
                ((symbolp fn) fn)
                ((and (consp fn) (eq (car fn) 'autoload)) nil)
                ((and (consp fn) (eq (car fn) 'macro))
                 (function-name-symbol (cdr fn)))
                #+sbcl
                ((typep fn 'cl:generic-function)
                 (let ((nm (sb-mop:generic-function-name fn)))
                   (and (symbolp nm) nm)))
                (t
                (multiple-value-bind (_lambda _closed name)
                    (cl:function-lambda-expression fn)
                  (declare (cl:ignore _lambda _closed))
                  (and (symbolp name) name))))))
	    (let* ((sym (function-name-symbol function))
	           (stored (and sym (function-get sym 'advertised-calling-convention)))
	           (fnobj
	             (cond
	              ;; Do not force autoload while looking up metadata.
	              ((and (symbolp function) (fboundp function))
	               (let ((sf (ignore-errors (symbol-function function))))
	                 (cond
	                  ((and (consp sf) (eq (car sf) 'autoload)) nil)
	                  ((and (consp sf) (eq (car sf) 'macro)) (cdr sf))
	                  ((cl:functionp sf) sf)
	                  #+sbcl
	                  ((typep sf 'sb-mop:funcallable-standard-object) sf)
	                  (t nil))))
	              ((cl:functionp function) function)
	              #+sbcl
	              ((typep function 'sb-mop:funcallable-standard-object) function)
	              (t nil)))
             (direct (and fnobj (gethash fnobj *advertised-calling-conventions*))))
        (or stored
            direct
            ;; Heuristic fallback: for the core `map.el` generics the only
            ;; advertised signature differences are deprecated trailing
            ;; `testfn` args.  When we don't have the stored advertised
            ;; convention, derive a best-effort value from the generic lambda
             ;; list.
            #+sbcl
            (when (typep function 'cl:generic-function)
              (let* ((ll (copy-list (sb-mop:generic-function-lambda-list function))))
                (when (and ll
                           (symbolp (car (last ll)))
                           (cl:string-equal "TESTFN" (cl:symbol-name (car (last ll)))))
                  (setf ll (butlast ll))
                  (when (and ll
                             (symbolp (car (last ll)))
                             (cl:string-equal "&OPTIONAL" (cl:symbol-name (car (last ll)))))
                    (setf ll (butlast ll))))
                ll))
            ;; When unknown, Emacs returns `t` (not nil).
            t)))))

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
        `(progn
           ;; Populate `current-load-list' so `load-history' + `symbol-file'
           ;; can report the defining file.
           (when (and (boundp 'current-load-list) (listp current-load-list))
             (push (cons 'defun ',name) current-load-list))
           (cl:defmacro ,name ,lambda-list
             ,@(when doc* (list doc*))
             ,@rest)
           ;; Mirror upstream: run the definition through `defalias` so advice
           ;; and other `defalias-fset-function` users can observe redefs.
           (let ((mf (cl:macro-function ',name)))
             (defalias ',name
               (cons 'macro
                     (lambda (&rest args)
                       (funcall mf (cons ',name args) nil)))))
           ',name))))

(cl:defmacro defun (name lambda-list &body body)
  "Define a function without mutating CL package symbols.

If NAME lives in the CL package, ignore the definition (this avoids
trying to redefine locked symbols while loading upstream ELisp)."
  (if (and (symbolp name) (eq (symbol-package name) (find-package "CL")))
      `(progn ',name)
      (let* ((doc (and body (stringp (car body)) (car body)))
             (doc* (and doc (if (cl:stringp doc) doc (%elisp-string->cl-string doc))))
             (tail (if doc (cdr body) body))
             (interactive-form
               (and tail
                    (consp (car tail))
                    (eq (caar tail) 'interactive)
                    ;; Emacs returns (interactive nil) for (interactive).
                    (let ((form (car tail)))
                      (if (null (cdr form)) '(interactive nil) form))))
             (rest (if interactive-form (cdr tail) tail)))
        `(progn
           ;; Populate `current-load-list' so `load-history' + `symbol-file'
           ;; can report the defining file for TYPE = 'defun.
           (when (and (boundp 'current-load-list) (listp current-load-list))
             (push (cons 'defun ',name) current-load-list))
           (cl:defun ,name ,lambda-list
             ,@(when doc* (list doc*))
             ,@rest)
           ;; Mirror upstream: run the definition through `defalias` so advice
           ;; and other `defalias-fset-function` users can observe redefs.
           (defalias ',name (cl:function ,name))
           ;; Provide a stable, structured arglist for callers like `advice.el`.
           ;; Emacs generally prefers an advertised calling convention when
           ;; present (and falls back to less reliable introspection).
           (ignore-errors
             (set-advertised-calling-convention ',name ',lambda-list))
           ,@(when interactive-form
               `((function-put ',name 'interactive-form ',interactive-form)))
           ',name))))

(cl:defmacro defsubst (name lambda-list &body body)
  "ELisp-ish DEFSUBST (currently just DEFUN)."
  `(defun ,name ,lambda-list ,@body))

(cl:defun equal (a b)
  (cond
   ((and (stringp a) (stringp b))
    (cl:string= (string-to-multibyte a) (string-to-multibyte b)))
   ;; In Emacs, anonymous lambdas can be compared structurally (not just by EQ),
   ;; which is relied upon by `nadvice` (e.g. `advice-remove` with a fresh
   ;; `(lambda ...)` form).
   ((and (cl:functionp a) (cl:functionp b))
    (or (eq a b)
        (multiple-value-bind (la _closed-a name-a) (cl:function-lambda-expression a)
          (declare (cl:ignore _closed-a))
          (multiple-value-bind (lb _closed-b name-b) (cl:function-lambda-expression b)
            (declare (cl:ignore _closed-b))
            (cond
             ((and la lb) (equal la lb))
             ;; SBCL may drop lambda expressions for compiled functions.  As a
             ;; fallback, compare anonymous lambda "names" (which include the
             ;; lambda list + source file) structurally.
             ((and (consp name-a) (eq (car name-a) 'lambda)
                   (consp name-b) (eq (car name-b) 'lambda))
              (equal name-a name-b))
             (t nil))))))
   ((and (consp a) (consp b))
    (and (equal (car a) (car b))
         (equal (cdr a) (cdr b))))
   ((and (typep a 'elisp-char-table) (typep b 'elisp-char-table))
    (and (equal (elisp-char-table-type a) (elisp-char-table-type b))
         (equal (elisp-char-table-default a) (elisp-char-table-default b))
         (equal (elisp-char-table-parent a) (elisp-char-table-parent b))
         (equal (elisp-char-table-extra a) (elisp-char-table-extra b))
         (equal (elisp-char-table-data a) (elisp-char-table-data b))))
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
   #+sbcl
   ((typep object 'sb-pcl::built-in-class) 'built-in-class)
   #+sbcl
   ((typep object 'sb-pcl::structure-class) 'cl-structure-class)
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

(cl:defun string-to-syntax (syntax)
  "Bring-up subset of ELisp `string-to-syntax'."
  (%syntax-entry-from-spec syntax))

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
(make-variable-buffer-local 'enable-multibyte-characters)
(make-variable-buffer-local 'selective-display)
(make-variable-buffer-local 'default-directory)
(make-variable-buffer-local 'buffer-file-name)
(make-variable-buffer-local 'buffer-auto-save-file-name)
(make-variable-buffer-local 'buffer-read-only)
(make-variable-buffer-local 'mark-ring)
(make-variable-buffer-local 'mark-active)
(make-variable-buffer-local 'mark-marker)
(make-variable-buffer-local 'transient-mark-mode)

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

(cl:defun kill-all-local-variables ()
  "Bring-up subset of the C primitive `kill-all-local-variables'."
  (unless (and (boundp '*current-buffer*) (elisp-buffer-p *current-buffer*))
    (error "ELISP:KILL-ALL-LOCAL-VARIABLES requires a current buffer"))
  (setf (elisp-buffer-locals *current-buffer*)
        (make-hash-table :test 'eq))
  nil)

(cl:defmacro setq-local (&rest pairs)
  "Bring-up subset of `setq-local'."
  (unless (evenp (length pairs))
    (error "ELISP:SETQ-LOCAL needs even number of args, got: ~S" pairs))
  (let ((forms nil))
    (loop for (var val) on pairs by #'cddr do
      (unless (symbolp var)
        (error "ELISP:SETQ-LOCAL only supports symbol vars, got: ~S" var))
      (push `(progn
               (make-local-variable ',var)
               (set ',var ,val))
            forms))
    `(progn ,@(nreverse forms))))

(defstruct elisp-process
  (name nil)
  (status 'run)
  (buffer nil)
  (mark nil)
  (plist nil)
  (command nil)
  (uiop-process nil)
  (input-stream nil)
  (output-stream nil)
  (filter nil)
  (sentinel nil)
  (exit-status nil)
  (output-generation 0))

(cl:defun %process--normalize (process)
  (cond
   ((null process) nil)
   ((elisp-process-p process) process)
   (t (error "ELISP:PROCESS expected process, got: ~S" process))))

(cl:defun %process--note-output (process)
  (when (elisp-process-p process)
    (cl:incf (elisp-process-output-generation process)))
  nil)

(cl:defun %process--ensure-exit-status (process)
  (let ((p (%process--normalize process)))
    (when (and p
               (eq (elisp-process-status p) 'run)
               (elisp-process-uiop-process p)
               (not (uiop:process-alive-p (elisp-process-uiop-process p))))
      (let* ((proc-info (elisp-process-uiop-process p))
             (code (uiop:wait-process proc-info))
             (event
               (if (and (integerp code) (zerop code))
                   (cl:format nil "finished~%")
                   (cl:format nil "exited abnormally with code ~D~%"
                              (or code -1))))
             (sentinel (elisp-process-sentinel p))
             (buf (elisp-process-buffer p)))
        (setf (elisp-process-exit-status p) code
              (elisp-process-status p) 'exit)
        (%process--note-output p)
        (cond
         ((functionp sentinel)
          (if (bufferp buf)
              (with-current-buffer buf
                (ignore-errors (funcall sentinel p event)))
              (ignore-errors (funcall sentinel p event))))
         ((bufferp buf)
          (with-current-buffer buf
            (let* ((m (or (elisp-process-mark p)
                          (let ((mm (make-marker)))
                            (set-marker mm (point-max) buf)
                            (setf (elisp-marker-insertion-type mm) t)
                            (setf (elisp-process-mark p) mm)
                            mm)))
                   (insert-at (or (marker-position m) (point-max)))
                   (ptm (make-marker)))
              (set-marker ptm (point) buf)
              (setf (elisp-marker-insertion-type ptm) nil)
              (goto-char insert-at)
              (let ((nm (elisp-process-name p)))
                (insert (string #\Newline) "Process "
                        (cond
                         ((stringp nm) (%elisp-string->cl-string nm))
                         ((symbolp nm) (symbol-name nm))
                         (t "?"))
                        " "
                        event))
              (set-marker m (point) buf)
              (goto-char (marker-position ptm))
              (set-marker ptm nil)))
          (%process--note-output p)))))
    p))

(cl:defun %process--resolve-buffer (buffer-or-name)
  (cond
   ((null buffer-or-name) nil)
   ((or (eq buffer-or-name t) (and (integerp buffer-or-name) (zerop buffer-or-name)))
    (current-buffer))
   ((stringp buffer-or-name) (get-buffer-create buffer-or-name))
   ((bufferp buffer-or-name) buffer-or-name)
   (t
    (error "ELISP:PROCESS buffer expected nil/t/0/string/buffer, got: ~S"
           buffer-or-name))))

(cl:defun %process--arg->string (a)
  (cond
   ((null a) nil)
   ((stringp a) (%elisp-string->cl-string a))
   ((symbolp a) (symbol-name a))
   (t (prin1-to-string a))))

(cl:defun %process--dispatch-output (process chunk)
  (let ((p (%process--normalize process)))
    (when (and p chunk (> (length chunk) 0))
      (let ((filter (elisp-process-filter p)))
        (cond
         ((functionp filter)
          (let ((buf (elisp-process-buffer p)))
            (if (bufferp buf)
                (with-current-buffer buf
                  (ignore-errors (funcall filter p chunk)))
                (ignore-errors (funcall filter p chunk)))))
         (t
          (let ((buf (elisp-process-buffer p)))
            (when (bufferp buf)
              (with-current-buffer buf
                (let* ((m (or (elisp-process-mark p)
                              (let ((mm (make-marker)))
                                (set-marker mm (point-max) buf)
                                (setf (elisp-marker-insertion-type mm) t)
                                (setf (elisp-process-mark p) mm)
                                mm)))
                       (insert-at (or (marker-position m) (point-max)))
                       (pt (point)))
                  (cond
                   ((= pt insert-at)
                    (goto-char insert-at)
                    (insert chunk)
                    (set-marker m (point) buf))
                   (t
                    (let ((ptm (make-marker)))
                      (set-marker ptm pt buf)
                      (setf (elisp-marker-insertion-type ptm) nil)
                      (goto-char insert-at)
                      (insert chunk)
                      (set-marker m (point) buf)
                      (goto-char (marker-position ptm))
                      (set-marker ptm nil)))))))))))
      (%process--note-output p)))
  nil)

(cl:defun process-mark (process)
  "Bring-up subset of the C primitive `process-mark'."
  (let ((p (%process--normalize process)))
    (cond
     ((null p) nil)
     (t
      (or (elisp-process-mark p)
          (let ((buf (elisp-process-buffer p)))
            (when (bufferp buf)
              (with-current-buffer buf
                (let ((m (make-marker)))
                  (set-marker m (point-max) buf)
                  (setf (elisp-marker-insertion-type m) t)
                  (setf (elisp-process-mark p) m)
                  m)))))))))

(cl:defun %process--start-output-thread (process)
  #+sbcl
  (let* ((p (%process--normalize process))
         (stream (and p (elisp-process-output-stream p))))
    (when (and p stream)
      (sb-thread:make-thread
       (lambda ()
         (unwind-protect
             (let ((buf (cl:make-string 4096)))
               (loop
                 (let ((n (cl:read-sequence buf stream)))
                   (when (<= n 0)
                     (return))
                   (%process--dispatch-output p (cl:subseq buf 0 n)))))
           (ignore-errors (cl:close stream))
           (ignore-errors (%process--ensure-exit-status p))))
       :name (cl:format nil "clemacs-process-output[~A]" (or (elisp-process-name p) "?")))))
  #-sbcl
  nil)

(cl:defun processp (object)
  "Bring-up subset of ELisp `processp'."
  (and (elisp-process-p object) t))

(cl:defun process-status (process)
  "Bring-up subset of the C primitive `process-status'."
  (cond
   ((null process) nil)
   ((elisp-process-p process)
    (%process--ensure-exit-status process)
    (elisp-process-status process))
   (t (error "ELISP:PROCESS-STATUS expected process, got: ~S" process))))

(cl:defun process-live-p (process)
  "Bring-up subset of ELisp `process-live-p'."
  (let ((p (%process--normalize process)))
    (and p
         (eq (process-status p) 'run)
         t)))

(cl:defun process-name (process)
  "Bring-up subset of the C primitive `process-name'."
  (let ((p (%process--normalize process)))
    (cond
     ((null p) nil)
     (t (or (elisp-process-name p) (string-to-unibyte ""))))))

(cl:defun process-id (process)
  "Bring-up subset of the C primitive `process-id'."
  (let ((p (%process--normalize process)))
    (cond
     ((null p) nil)
     ((integerp (elisp-process-exit-status p)) nil)
     ((and (elisp-process-uiop-process p)
           (uiop:process-alive-p (elisp-process-uiop-process p)))
      (uiop:process-info-pid (elisp-process-uiop-process p)))
     (t nil))))

(cl:defun process-command (process)
  "Bring-up subset of the C primitive `process-command'."
  (let ((p (%process--normalize process)))
    (cond
     ((null p) nil)
     (t (or (elisp-process-command p) nil)))))

(cl:defun process-plist (process)
  "Bring-up subset of the C primitive `process-plist'."
  (cond
   ((null process) nil)
   ((elisp-process-p process) (or (elisp-process-plist process) nil))
   (t (error "ELISP:PROCESS-PLIST expected process, got: ~S" process))))

(cl:defun set-process-plist (process plist)
  "Bring-up subset of the C primitive `set-process-plist'."
  (cond
   ((null process) nil)
   ((elisp-process-p process)
    (setf (elisp-process-plist process) plist)
    plist)
   (t (error "ELISP:SET-PROCESS-PLIST expected process, got: ~S" process))))

(cl:defun process-buffer (process)
  "Bring-up subset of the C primitive `process-buffer'."
  (cond
   ((null process) nil)
   ((elisp-process-p process) (elisp-process-buffer process))
   (t (error "ELISP:PROCESS-BUFFER expected process, got: ~S" process))))

(cl:defvar *elisp-process-list* nil)

(cl:defun process-list ()
  "Bring-up subset of the C primitive `process-list'."
  (remove nil
          (mapcar (lambda (p) (and (elisp-process-p p) p))
                  *elisp-process-list*)))

(cl:defun process-filter (process)
  "Bring-up subset of the C primitive `process-filter'."
  (let ((p (%process--normalize process)))
    (and p (elisp-process-filter p))))

(cl:defun set-process-filter (process filter)
  "Bring-up subset of the C primitive `set-process-filter'."
  (let ((p (%process--normalize process)))
    (unless (and p (or (null filter) (functionp filter)))
      (error "ELISP:SET-PROCESS-FILTER expected process + function/nil, got: ~S ~S"
             process filter))
    (setf (elisp-process-filter p) filter)
    filter))

(cl:defun process-sentinel (process)
  "Bring-up subset of the C primitive `process-sentinel'."
  (let ((p (%process--normalize process)))
    (and p (elisp-process-sentinel p))))

(cl:defun set-process-sentinel (process sentinel)
  "Bring-up subset of the C primitive `set-process-sentinel'."
  (let ((p (%process--normalize process)))
    (unless (and p (or (null sentinel) (functionp sentinel)))
      (error "ELISP:SET-PROCESS-SENTINEL expected process + function/nil, got: ~S ~S"
             process sentinel))
    (setf (elisp-process-sentinel p) sentinel)
    sentinel))

(cl:defun process-send-string (process string)
  "Bring-up subset of the C primitive `process-send-string'."
  (let ((p (%process--normalize process)))
    (unless (and p (stringp string))
      (error "ELISP:PROCESS-SEND-STRING expected process + string, got: ~S ~S"
             process string))
    (let ((s (elisp-process-input-stream p)))
      (unless (streamp s)
        (error "ELISP:PROCESS-SEND-STRING no input stream for process: ~S" p))
      (write-string (%elisp-string->cl-string string) s)
      (finish-output s))
    nil))

(cl:defun process-send-eof (&optional process)
  "Bring-up subset of the C primitive `process-send-eof'."
  (let ((p (%process--normalize process)))
    (when p
      (let ((s (elisp-process-input-stream p)))
        (when (streamp s)
          (ignore-errors (cl:close s))
          (setf (elisp-process-input-stream p) nil))))
    nil))

(cl:defun accept-process-output (&optional process seconds millis _just-this-one)
  "Bring-up subset of the C primitive `accept-process-output'."
  (declare (cl:ignore _just-this-one))
  (let* ((p (%process--normalize process))
         (timeout (+
                   (or (and seconds (%num seconds)) 0)
                   (if (and millis (integerp millis))
                       (/ millis 1000.0)
                       0)))
         (deadline (+ (get-internal-real-time)
                      (truncate (* internal-time-units-per-second timeout))))
         (start-gen (and p (elisp-process-output-generation p))))
    (loop
      (when (null p)
        (when (>= (get-internal-real-time) deadline)
          (return-from accept-process-output nil))
        (cl:sleep 0.01)
        (return-from accept-process-output nil))
      (process-status p)
      (when (not (process-live-p p))
        (return-from accept-process-output t))
      (when (and start-gen
                 (/= start-gen (elisp-process-output-generation p)))
        (return-from accept-process-output t))
      (when (>= (get-internal-real-time) deadline)
        (return-from accept-process-output nil))
      (cl:sleep 0.01))))

(cl:defun delete-process (process)
  "Bring-up subset of the C primitive `delete-process'."
  (let ((p (%process--normalize process)))
    (when p
      (let ((proc-info (elisp-process-uiop-process p)))
        (when (and proc-info (uiop:process-alive-p proc-info))
          (ignore-errors (uiop:terminate-process proc-info :urgent t))))
      (ignore-errors (%process--ensure-exit-status p))
      (setf *elisp-process-list* (delq p *elisp-process-list*)))
    nil))

(cl:defun make-process (&rest plist)
  "Bring-up subset of the C primitive `make-process'."
  (let* ((name (plist-get plist :name))
         (_coding (plist-get plist :coding))
         (_noquery (plist-get plist :noquery))
         (buffer (plist-get plist :buffer))
         (command (plist-get plist :command)))
    (declare (cl:ignore _coding _noquery))
    (unless (stringp name)
      (error "ELISP:MAKE-PROCESS expected :name string, got: ~S" name))
    (unless (and (listp command) (consp command))
      (error "ELISP:MAKE-PROCESS expected :command non-empty list, got: ~S" command))
    (let* ((argv (remove nil (mapcar #'%process--arg->string command)))
           (buf (%process--resolve-buffer buffer))
           (proc-info (uiop:launch-program argv
                                           :input :stream
                                           :output :stream
                                           :error-output :output
                                           :external-format :utf-8))
           (mark (and (bufferp buf)
                      (with-current-buffer buf
                        (let ((m (make-marker)))
                          (set-marker m (point-max) buf)
                          (setf (elisp-marker-insertion-type m) t)
                          m))))
           (p (make-elisp-process :name name
                                  :status 'run
                                  :buffer buf
                                  :mark mark
                                  :plist nil
                                  :command argv
                                  :uiop-process proc-info
                                  :input-stream (uiop:process-info-input proc-info)
                                  :output-stream (uiop:process-info-output proc-info)
                                  :filter nil
                                  :sentinel nil
                                  :exit-status nil
                                  :output-generation 0)))
      (push p *elisp-process-list*)
      (%process--start-output-thread p)
      p)))

(cl:defun start-process (name buffer program &rest program-args)
  "Bring-up subset of the C primitive `start-process'."
  (unless (stringp name)
    (error "ELISP:START-PROCESS expected string NAME, got: ~S" name))
  (unless (stringp program)
    (error "ELISP:START-PROCESS expected string PROGRAM, got: ~S" program))
  (make-process :name name
                :buffer buffer
                :command (cons program program-args)))

(cl:defun get-buffer-process (&optional buffer-or-name)
  "Bring-up subset of ELisp `get-buffer-process'."
  (let ((buf (cond
              ((null buffer-or-name) (current-buffer))
              (t (or (get-buffer buffer-or-name)
                     (error "ELISP:GET-BUFFER-PROCESS no such buffer: ~S"
                            buffer-or-name))))))
    (dolist (p *elisp-process-list* nil)
      (when (and (elisp-process-p p)
                 (eq (elisp-process-buffer p) buf))
        (return-from get-buffer-process p)))))

(cl:defun process-query-on-exit-flag (process)
  "Bring-up subset of the C primitive `process-query-on-exit-flag'."
  (cond
   ((null process) nil)
   ((elisp-process-p process)
    (let ((plist (elisp-process-plist process)))
      (and (listp plist) (getf plist 'query-on-exit-flag))))
   (t
    (error "ELISP:PROCESS-QUERY-ON-EXIT-FLAG expected process, got: ~S" process))))

(cl:defun emacs-pid ()
  "Bring-up subset of the C primitive `emacs-pid'."
  #+sbcl
  (sb-posix:getpid)
  #-sbcl
  0)

(cl:defun %process-attributes/split-whitespace (s)
  (let ((tokens nil)
        (start nil))
    (labels ((emit (end)
               (when start
                 (let ((tok (subseq s start end)))
                   (push tok tokens))
                 (setf start nil))))
      (loop for i from 0 below (length s) do
        (let ((ch (char s i)))
          (if (or (char= ch #\Space) (char= ch #\Tab))
              (emit i)
              (unless start
                (setf start i)))))
      (emit (length s)))
    (nreverse tokens)))

(cl:defun %process-attributes/join-with-spaces (strings)
  (let ((out (make-string-output-stream))
        (firstp t))
    (dolist (s strings)
      (if firstp
          (setf firstp nil)
          (write-char #\Space out))
      (write-string s out))
    (get-output-stream-string out)))

(cl:defun %process-attributes/parse-ps-line (line)
  ;; Expected columns: euid user egid group comm state ppid args...
  (let* ((tokens (%process-attributes/split-whitespace line)))
    (when (< (length tokens) 7)
      (return-from %process-attributes/parse-ps-line nil))
    (let* ((euid (parse-integer (nth 0 tokens) :junk-allowed t))
           (user (nth 1 tokens))
           (egid (parse-integer (nth 2 tokens) :junk-allowed t))
           (group (nth 3 tokens))
           (comm (nth 4 tokens))
           (state (nth 5 tokens))
           (ppid (parse-integer (nth 6 tokens) :junk-allowed t))
           (args (and (nthcdr 7 tokens)
                      (%process-attributes/join-with-spaces (nthcdr 7 tokens)))))
      (remove nil
              (list
               (and euid (cons 'euid euid))
               (and user (cons 'user user))
               (and egid (cons 'egid egid))
               (and group (cons 'group group))
               (and comm (cons 'comm comm))
               (and state (cons 'state state))
               (and ppid (cons 'ppid ppid))
               (and args (cons 'args args)))))))

(cl:defun process-attributes (pid)
  "Bring-up subset of the C primitive `process-attributes'."
  (unless (integerp pid)
    (error "ELISP:PROCESS-ATTRIBUTES expected integer PID, got: ~S" pid))
  ;; The full Emacs primitive is platform-dependent and can expose many fields.
  ;; For bring-up, we rely on `ps` and expose a small, high-ROI subset.
  (multiple-value-bind (out _err code)
      (uiop:run-program (list "ps"
                              "-p" (prin1-to-string pid)
                              "-o" "uid="
                              "-o" "user="
                              "-o" "gid="
                              "-o" "group="
                              "-o" "comm="
                              "-o" "state="
                              "-o" "ppid="
                              "-o" "args=")
                        :output :string
                        :error-output :string
                        :ignore-error-status t)
    (declare (cl:ignore _err))
    (cond
     ((not (and (integerp code) (zerop code))) nil)
     (t
      (let ((line (cl:string-trim '(#\Space #\Tab #\Newline #\Return) out)))
        (and (> (length line) 0)
             (%process-attributes/parse-ps-line line)))))))

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

(cl:defun default-toplevel-value (symbol)
  "Bring-up subset of the C primitive `default-toplevel-value'."
  (unless (symbolp symbol)
    (error "ELISP:DEFAULT-TOPLEVEL-VALUE expected symbol, got: %S" symbol))
  (handler-case
      #+sbcl (sb-ext:symbol-global-value symbol)
      #-sbcl (cl:symbol-value symbol)
    (unbound-variable ()
      (signal 'void-variable (list symbol)))))

(cl:defun set-default-toplevel-value (symbol value)
  "Bring-up subset of the C primitive `set-default-toplevel-value'."
  (unless (symbolp symbol)
    (error "ELISP:SET-DEFAULT-TOPLEVEL-VALUE expected symbol, got: %S" symbol))
  #+sbcl (setf (sb-ext:symbol-global-value symbol) value)
  #-sbcl (setf (cl:symbol-value symbol) value)
  nil)

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

;; Core editor mode variable referenced by upstream `cl-generic` context tests.
(defvar overwrite-mode nil)

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
      ;; Our ELisp macro objects store an "args expander" (called with the macro
      ;; argument list).  Bridge that to CL's macro-function calling convention
      ;; (WHOLE-FORM ENV) so CL evaluation of loaded ELisp can expand macros too.
      ;;
      ;; Capture the cons cell so later `nadvice` mutations of the cdr (wrapping
      ;; the expander) are observed by CL macroexpansion.
      (let ((cell definition))
        (setf (cl:macro-function symbol)
              (lambda (whole-form _env)
                (declare (cl:ignore _env))
                (cl:apply (cdr cell) (cdr whole-form))))))
     ((cl:functionp definition)
      (setf (cl:fdefinition symbol) definition))
     (t
      (setf (cl:fdefinition symbol)
	            (lambda (&rest args)
	              (cl:apply (%resolve-function symbol) args))))))
	  (let ((acc (ignore-errors (function-get symbol 'advertised-calling-convention))))
	    (when acc
	      (let ((fnobj (ignore-errors (%resolve-function symbol))))
	        (when fnobj
	          (setf (gethash fnobj *advertised-calling-conventions*) acc)))))
	  symbol)

(cl:defun fmakunbound (symbol)
  "Unset SYMBOL's function cell value.

In clemacs, this also clears the internal function-cell map so `fboundp'
reflects the unbound state (required by cl-generic tests)."
  (unless (symbolp symbol)
    (signal 'wrong-type-argument (list 'symbolp symbol)))
  (fset symbol nil)
  symbol)

(cl:defun defalias (symbol definition &optional _docstring)
  "Alias SYMBOL's function definition to DEFINITION."
  (declare (cl:ignore _docstring))
  (when (and (symbolp symbol)
             (eq (symbol-package symbol) (find-package "CL")))
    (return-from defalias symbol))
  (let* ((hook (and (symbolp symbol) (get symbol 'defalias-fset-function)))
         (out (if hook
                  (funcall hook symbol definition)
                  (fset symbol definition))))
    ;; Bridge Emacs's "gv setter symbol" convention into CL's `(setf F)` naming,
    ;; so host CL `setf` can call setters defined via gv/cl-generic.
    ;;
    ;; `gv-setter` returns an interned symbol named like "(setf foo)" (a symbol,
    ;; not a list).  Many upstream files (including cl-generic-tests) use `setf`
    ;; on function call places, which in CL calls the function named `(setf foo)`.
    (when (and (symbolp symbol) (cl:fboundp symbol))
      (let* ((nm (%elisp-string->cl-string (symbol-name symbol)))
             (n (cl:length nm)))
        (when (and (>= n 7)
                   (cl:string= (cl:subseq nm 0 6) "(setf ")
                   (cl:char= (cl:aref nm (1- n)) #\)))
          (let* ((inner (cl:subseq nm 6 (1- n)))
                 (base (ignore-errors (intern inner (symbol-package symbol)))))
            (when (symbolp base)
              (ignore-errors
               (setf (cl:fdefinition (list 'setf base)) (cl:fdefinition symbol))))))))
    out))

(cl:defmacro while (test &body body)
  "ELisp-ish WHILE."
  `(loop while ,test do (progn ,@body)))

(cl:defmacro with-no-warnings (&body body)
  "Bring-up subset of ELisp `with-no-warnings'."
  `(progn ,@body))

(cl:defun plist-get (plist prop &optional predicate)
  "Bring-up subset of ELisp `plist-get'.

When PREDICATE is non-nil, use it to compare property keys (Emacs 29+)."
  (let ((pred (or predicate #'eq))
        (p plist))
    (loop while (consp p) do
      (when (funcall pred (car p) prop)
        (return (cadr p)))
      (setf p (cddr p))
      finally (return nil))))

(cl:defun plist-put (plist prop value &optional predicate)
  "Bring-up subset of ELisp `plist-put'.

When PREDICATE is non-nil, use it to compare property keys (Emacs 29+)."
  (let ((pred (or predicate #'eq))
        (p plist))
    (loop while (consp p) do
      (unless (consp (cdr p))
        (signal 'wrong-type-argument (list 'plistp plist)))
      (when (funcall pred (car p) prop)
        (setf (cadr p) value)
        (return-from plist-put plist))
      (setf p (cddr p)))
    ;; If we fell off the end via an improper tail (e.g. (a 1 . b)), treat it
    ;; as a malformed plist for insertion and signal instead of mutating it.
    (when p
      (signal 'wrong-type-argument (list 'plistp plist)))
    (cond
     ((null plist)
      (list prop value))
     (t
      ;; Destructively append so callers like `map-put!' don't need to replace
      ;; the head pointer of PLIST.
      (let ((tail plist))
        (loop while (consp (cdr tail)) do (setf tail (cdr tail)))
        (setf (cdr tail) (list prop value))
        plist)))))

(cl:defun plist-member (plist prop &optional predicate)
  "Bring-up subset of ELisp `plist-member'.

When PREDICATE is non-nil, use it to compare property keys (Emacs 29+)."
  (let ((pred (or predicate #'eq))
        (p plist))
    (loop
      (cond
       ((null p) (return nil))
       ((not (consp p))
        (signal 'wrong-type-argument (list 'plistp plist)))
       ((funcall pred (car p) prop)
        (return p))
       ((null (cdr p))
        ;; Odd length: treat as terminated.
        (return nil))
       ((not (consp (cdr p)))
        ;; Improper tail: signal if we didn't match above.
        (signal 'wrong-type-argument (list 'plistp plist)))
       (t
        (setf p (cddr p)))))))

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

(cl:define-setf-expander map-elt (map key &optional default testfn &environment env)
  "CL:SETF expansion for ELisp `map-elt'.

This is an approximation of `map.el`'s gv-expander, expressed as a Common Lisp
setf expander so it works even when ELisp `setf` isn't available."
  (multiple-value-bind (map-temps map-vals map-store-vars map-store-form map-access)
      (cl:get-setf-expansion map env)
    (let ((k (gensym "KEY"))
          (d (gensym "DEFAULT"))
          (tf (gensym "TESTFN"))
          (new (gensym "NEW"))
          (map-var (gensym "MAP")))
      (cl:values
       (append map-temps (list k d tf))
       (append map-vals (list key default testfn))
       (list new)
       `(let* ((,map-var ,map-access))
          (handler-case
              (progn
                (map-put! ,map-var ,k ,new ,tf)
                (let (,@(loop for sv in map-store-vars collect `(,sv ,map-var)))
                  ,map-store-form)
                ,new)
            (elisp-signal (e)
              (if (eq (elisp-signal-symbol e) 'map-not-inplace)
                  (let* ((,map-var (map-insert ,map-var ,k ,new)))
                    (let (,@(loop for sv in map-store-vars collect `(,sv ,map-var)))
                      ,map-store-form)
                    ,new)
                  (cl:error e)))))
	       `(map-elt ,map-access ,k ,d ,tf)))))

(cl:define-setf-expander gv-deref (ref &environment env)
  "CL:SETF expansion for ELisp `gv-deref'.

Upstream defines a gv-setter for `gv-deref' (so `(setf (gv-deref ref) v)` calls
the setter stored in REF).  We mirror that behavior for host CL `setf`."
  (declare (cl:ignore env))
  (let ((r (gensym "REF"))
        (new (gensym "NEW")))
    (cl:values
     (list r)
     (list ref)
     (list new)
     `(progn
        (funcall (cdr ,r) ,new)
        ,new)
     `(gv-deref ,r))))

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
