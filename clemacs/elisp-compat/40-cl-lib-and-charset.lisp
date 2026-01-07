(in-package #:elisp)

(cl:defmacro cl-progv (symbols values &body body)
  "Bring-up subset of cl-lib's `cl-progv'."
  `(cl:progv ,symbols ,values ,@body))

(cl:defun %cl-destructuring-bind-check-key-list (key-list allowed-keys)
  (let ((xs key-list))
    (loop while (keywordp (car-safe xs)) do
      (let ((k (car xs)))
        (unless (consp (cdr xs))
          (error "Value expected after keyword %S in %S" k key-list))
        (unless (memq k allowed-keys)
          (error "Keyword argument %S not one of %S" k allowed-keys))
        (setf xs (cddr xs)))))
  t)

(cl:defmacro cl-destructuring-bind (lambda-list expr &body body)
  "Minimal subset of cl-lib's `cl-destructuring-bind'."
  (labels ((&-symbol-p (x)
             (and (symbolp x)
                  (let ((nm (symbol-name x)))
                    (and (plusp (length nm))
                         (= (aref nm 0) (char-code #\&))))))
           (key-arg->keyword (spec)
             (cond
              ((symbolp spec) (intern (symbol-name spec) :keyword))
              ((consp spec)
               (let ((head (car spec)))
                 (cond
                  ((symbolp head) (intern (symbol-name head) :keyword))
                  ((and (consp head) (keywordp (car head))) (car head))
                  (t nil))))
              (t nil)))
           (allowed-keys-from-key-lambda-list (ll)
             (let* ((tail (cdr (member '&key ll))))
               (when (member '&allow-other-keys tail)
                 (return-from allowed-keys-from-key-lambda-list nil))
               (remove nil
                       (loop for spec in tail
                             while (not (&-symbol-p spec))
                             collect (key-arg->keyword spec)))))
           (validation-forms (ll value-form)
             (cond
              ((and (consp ll) (eq (car ll) '&key))
               (let ((allowed (allowed-keys-from-key-lambda-list ll)))
                 (when allowed
                   `((%cl-destructuring-bind-check-key-list ,value-form ',allowed)))))
              ((and (consp ll)
                    (consp (car ll))
                    (eq (caar ll) '&key))
               (let ((allowed (allowed-keys-from-key-lambda-list (car ll))))
                 (when allowed
                   `((when (consp ,value-form)
                       (%cl-destructuring-bind-check-key-list (car ,value-form) ',allowed))))))
              (t nil))))
    (let ((tmp (gensym "CL-DESTRUCTURING-BIND-EXPR-")))
      `(let ((,tmp ,expr))
         ,@(validation-forms lambda-list tmp)
         (cl:destructuring-bind ,lambda-list ,tmp ,@body)))))

(cl:defun cl-plusp (x)
  "Bring-up subset of cl-lib's `cl-plusp'."
  (and (numberp x) (> x 0)))

(cl:defmacro cl-macrolet (bindings &body body &environment env0)
  "Bring-up subset of cl-lib's `cl-macrolet'.

ERT's `should' macro calls `macroexpand-all' and passes
`macroexpand-all-environment'.  In Emacs, `cl-macrolet' extends that
environment with its locally-bound macros.

In CL, the body is macroexpanded/compiled before any runtime LET bindings
exist, so we do the binding at macroexpansion time and pre-expand BODY under
an augmented SBCL lexical environment."
  (labels
      ((normalize-lambda-list (lambda-list)
         (labels ((rw (xs)
                    (cond
                     ((null xs) nil)
                     ((and (consp xs) (eq (car xs) '&body))
                      (cons '&rest (rw (cdr xs))))
                     (t (cons (car xs) (rw (cdr xs)))))))
           (rw lambda-list)))
       (strip-environment (lambda-list)
         (let ((out nil)
               (env-var nil))
           (loop while lambda-list do
             (let ((x (pop lambda-list)))
               (cond
                ((eq x '&environment)
                 (setf env-var (pop lambda-list)))
                (t
                 (push x out)))))
           (cl:values (nreverse out) env-var)))
       (binding->macro (binding)
         (destructuring-bind (name lambda-list &rest mbody) binding
           (let* ((lambda-list (normalize-lambda-list lambda-list)))
             (multiple-value-bind (lambda-list env-var)
                 (strip-environment lambda-list)
               (let ((body-form (if env-var
                                    `(let ((,env-var env)) (progn ,@mbody))
                                    `(progn ,@mbody))))
                 (list name
                       (cl:eval
                        `(lambda (form env)
                           (declare (ignorable form env))
                           (let ((args (cdr form)))
                             (declare (ignorable args))
                             (destructuring-bind ,lambda-list args
                               ,body-form)))))))))))
    (let* ((macro-defs (mapcar #'binding->macro bindings))
           (env1 (sb-cltl2:augment-environment env0 :macro macro-defs)))
      (let ((macroexpand-all-environment env1))
        (declare (special macroexpand-all-environment))
        ;; Keep expansion shallow: we only need to macroexpand top-level forms
        ;; so ERT's `should' macro sees `macroexpand-all-environment'.  A deep
        ;; walker can easily break code that relies on backquote internals.
        (let ((expanded-body (mapcar (lambda (f) (cl:macroexpand f env1)) body)))
          `(progn ,@expanded-body))))))

(cl:defmacro cl-flet (bindings &body body)
  "Minimal subset of cl-lib's `cl-flet'."
  `(cl:flet ,bindings ,@body))

(cl:defmacro cl-labels (bindings &body body)
  "Minimal subset of cl-lib's `cl-labels'."
  `(cl:labels ,bindings ,@body))

(cl:defmacro cl-loop (&rest clauses)
  "Minimal subset of cl-lib's `cl-loop'."
  (labels ((rewrite-by (x)
             (if (and (consp x) (eq (car x) 'function) (= (length x) 2))
                 (let ((arg (cadr x)))
                   (cond
                    ((symbolp arg) `(cl:function ,arg))
                    ((and (consp arg) (eq (car arg) 'lambda)) `(cl:function ,arg))
                    (t x)))
                 x))
           (rewrite-across (xs)
             ;; cl-lib's `cl-loop' iterates strings by character codes
             ;; (because `aref' returns integers).  CL:LOOP iterates strings
             ;; by CL characters, which breaks a number of upstream helpers
             ;; (notably ERT explainers).  Rewrite:
             ;;   for VAR across SEQ
             ;; into:
             ;;   for SEQG = SEQ then SEQG
             ;;   for IG from 0 below (length SEQG)
             ;;   for VAR = (aref SEQG IG)
             (let ((out nil)
                   (bindings nil)
                   (rest xs))
               (loop while rest do
                 (cond
                  ((and (consp rest)
                        (cl:member (car rest) '(for as) :test #'eq)
                        (consp (cdr rest))
                        (symbolp (cadr rest))
                        (consp (cddr rest))
                        (eq (caddr rest) 'across)
                        (consp (cdddr rest)))
                   (let* ((kw (car rest))
                          (var (cadr rest))
                          (seq (cadddr rest))
                          (seqg (gensym "SEQ"))
                          (ig (gensym "I")))
                     (declare (cl:ignore kw))
                     (push (list seqg seq) bindings)
                     (setf rest (cddddr rest))
                     ;; OUT is built in reverse order.
                     (dolist (x (list 'for ig 'from 0 'below `(length ,seqg)
                                      'for var '= `(aref ,seqg ,ig)))
                       (push x out))))
                  (t
                   (push (car rest) out)
                   (setf rest (cdr rest)))))
               (cl:values (nreverse bindings) (nreverse out))))
           (walk (xs)
             (cond
              ((null xs) nil)
              ((eq (car xs) 'by)
               (cons 'by (cons (rewrite-by (cadr xs)) (walk (cddr xs)))))
              (t (cons (car xs) (walk (cdr xs)))))))
    (multiple-value-bind (bindings clauses*)
        (rewrite-across clauses)
      (if (null bindings)
          `(cl:loop ,@(walk clauses*))
          `(cl:let ,bindings
             (cl:loop ,@(walk clauses*)))))))

(cl:defmacro cl-do (bindings endtest &body body)
  "Minimal subset of cl-lib's `cl-do'."
  `(cl:do ,bindings ,endtest ,@body))

(cl:defmacro cl-etypecase (keyform &rest clauses)
  "Bring-up subset of cl-lib's `cl-etypecase'."
  `(cl:etypecase ,keyform ,@clauses))

(cl:defun cl-typep (object type)
  "Bring-up subset of cl-lib's `cl-typep'."
  (cond
   ((and (consp type) (eq (car type) 'satisfies) (= (length type) 2))
    (funcall (cadr type) object))
   (t
    (typep object type))))

(cl:defmacro cl-check-type (form type &optional _string)
  "Bring-up subset of cl-lib's `cl-check-type'."
  (declare (cl:ignore _string))
  (let ((tmp (gensym "VAL")))
    `(let ((,tmp ,form))
       (unless (cl-typep ,tmp ',type)
         (error "Wrong type: expected %S, got %S" ',type ,tmp))
       nil)))

(cl:defmacro cl-incf (place &optional (delta 1))
  "Minimal subset of cl-lib's `cl-incf'."
  `(cl:incf ,place ,delta))

(cl:defmacro cl-return (&optional value)
  "Minimal subset of cl-lib's `cl-return'."
  `(cl:return ,value))

(cl:defmacro cl-return-from (name &optional value)
  "Minimal subset of cl-lib's `cl-return-from'."
  `(cl:return-from ,name ,value))

(cl:defmacro cl-block (name &body body)
  "Minimal subset of cl-lib's `cl-block'."
  `(cl:block ,name ,@body))

(cl:defmacro cl-case (keyform &rest clauses)
  "Minimal subset of cl-lib's `cl-case'."
  `(cl:case ,keyform ,@clauses))

(cl:defmacro cl-ecase (keyform &rest clauses)
  "Minimal subset of cl-lib's `cl-ecase'."
  `(cl:ecase ,keyform ,@clauses))

(cl:defun cl-struct-p (_x)
  "Bring-up stub for cl-lib's `cl-struct-p'."
  (declare (cl:ignore _x))
  nil)

(cl:defun cl-intersection (list1 list2 &rest args &key (test 'eql) key &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-intersection'."
  (declare (cl:ignore args))
  (let ((test-fn
          (cond
           ((or (eq test 'eq) (eq test 'cl:eq)) #'cl:eq)
           ((or (eq test 'eql) (eq test 'cl:eql)) #'cl:eql)
           ((or (eq test 'equal) (eq test 'cl:equal)) #'cl:equalp)
           ((or (eq test 'equalp) (eq test 'cl:equalp)) #'cl:equalp)
           ((functionp test) test)
           (t (cl:error "ELISP:CL-INTERSECTION unsupported :test: ~S" test)))))
    (cl:intersection list1 list2 :test test-fn :key key)))

(cl:defun cl-set-difference (list1 list2 &rest args &key (test 'eql) key &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-set-difference'."
  (declare (cl:ignore args))
  (let ((test-fn
          (cond
           ((or (eq test 'eq) (eq test 'cl:eq)) #'cl:eq)
           ((or (eq test 'eql) (eq test 'cl:eql)) #'cl:eql)
           ((or (eq test 'equal) (eq test 'cl:equal)) #'cl:equalp)
           ((or (eq test 'equalp) (eq test 'cl:equalp)) #'cl:equalp)
           ((functionp test) test)
           (t (cl:error "ELISP:CL-SET-DIFFERENCE unsupported :test: ~S" test)))))
    (cl:set-difference list1 list2 :test test-fn :key key)))

(cl:defun cl-union (list1 list2 &rest args &key (test 'eql) key &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-union'."
  (declare (cl:ignore args))
  (let ((test-fn
          (cond
           ((or (eq test 'eq) (eq test 'cl:eq)) #'cl:eq)
           ((or (eq test 'eql) (eq test 'cl:eql)) #'cl:eql)
           ((or (eq test 'equal) (eq test 'cl:equal)) #'cl:equalp)
           ((or (eq test 'equalp) (eq test 'cl:equalp)) #'cl:equalp)
           ((functionp test) test)
           (t (cl:error "ELISP:CL-UNION unsupported :test: ~S" test)))))
    (cl:union list1 list2 :test test-fn :key key)))

(cl:defun cl-remove-if-not (predicate sequence &rest args &key &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-remove-if-not'."
  (apply #'cl:remove-if-not predicate sequence args))

(cl:defun cl-position (item sequence &rest args)
  "Bring-up subset of cl-lib's `cl-position'."
  (let* ((item (if (and (integerp item)
                        (stringp sequence)
                        ;; Only remap integer ITEM to a character when
                        ;; SEQUENCE is a multibyte (CL) string. Unibyte strings
                        ;; are byte vectors whose elements are integers.
                        (not (unibyte-string-p sequence)))
                   (or (code-char item) item)
                   item))
         (test (getf args :test 'eql))
         (test-fn
           (cond
            ((or (eq test 'eq) (eq test 'cl:eq)) #'cl:eq)
            ((or (eq test 'eql) (eq test 'cl:eql)) #'cl:eql)
            ((or (eq test 'equal) (eq test 'cl:equal)) #'cl:equalp)
            ((or (eq test 'equalp) (eq test 'cl:equalp)) #'cl:equalp)
            ((functionp test) test)
            (t (cl:error "ELISP:CL-POSITION unsupported :test: ~S" test))))
         (remapped-args
           (loop for (k v) on args by (cl:function cl:cddr)
                 collect k
                 collect (if (eq k :test) test-fn v))))
    (apply #'cl:position item sequence remapped-args)))

(cl:defun cl-gensym (&optional prefix)
  "Bring-up subset of cl-lib's `cl-gensym'."
  (let ((p (cond
            ((null prefix) "G")
            ((stringp prefix) prefix)
            ((symbolp prefix) (symbol-name prefix))
            (t (cl:error "ELISP:CL-GENSYM unsupported prefix: ~S" prefix)))))
    (gensym (string-upcase (%elisp-string->cl-string p)))))

(cl:defun cl-coerce (object type)
  "Bring-up subset of cl-lib's `cl-coerce'.

ELisp tends to pass type names as ELISP package symbols (e.g. `list'),
whereas CL:COERCE expects CL type names."
  (let ((type (if (symbolp type)
                 (intern (string-upcase (%elisp-string->cl-string (symbol-name type)))
                         (find-package "CL"))
                  type)))
    (coerce object type)))

(cl:defun cl-search (sequence1 sequence2 &rest args &key (test 'eql) &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-search'."
  (declare (cl:ignore args))
  (let ((test-fn
          (cond
           ((or (eq test 'eq) (eq test 'cl:eq)) #'cl:eq)
           ((or (eq test 'eql) (eq test 'cl:eql)) #'cl:eql)
           ((or (eq test 'equal) (eq test 'cl:equal)) #'cl:equalp)
           ((or (eq test 'equalp) (eq test 'cl:equalp)) #'cl:equalp)
           ((functionp test) test)
           (t (cl:error "ELISP:CL-SEARCH unsupported :test: ~S" test)))))
    (cl:search sequence1 sequence2 :test test-fn)))

(cl:defun cl-mismatch (sequence1 sequence2 &rest args &key (test 'eql) &allow-other-keys)
  "Bring-up subset of cl-lib's `cl-mismatch'."
  (declare (cl:ignore args))
  (let ((test-fn
          (cond
           ((or (eq test 'eq) (eq test 'cl:eq)) #'cl:eq)
           ((or (eq test 'eql) (eq test 'cl:eql)) #'cl:eql)
           ((or (eq test 'equal) (eq test 'cl:equal)) #'cl:equalp)
           ((or (eq test 'equalp) (eq test 'cl:equalp)) #'cl:equalp)
           ((functionp test) test)
           (t (cl:error "ELISP:CL-MISMATCH unsupported :test: ~S" test)))))
    (cl:mismatch sequence1 sequence2 :test test-fn)))

(cl:defun cl-remprop (symbol indicator)
  "Minimal subset of cl-lib's `cl-remprop'."
  (and (remprop symbol indicator) t))

(cl:defmacro cl-letf* (bindings &body body)
  "Bring-up subset of cl-lib's `cl-letf*'.

This is intentionally narrow: it supports the temporary rebinding patterns
we hit in upstream ERT bring-up (e.g. rebinding `(symbol-function 'message)`).
Unsupported places error with a clear message."
  (labels
      ((expand (bs)
         (if (null bs)
             `(progn ,@body)
             (destructuring-bind (place expr) (car bs)
               (cond
                ;; cl-letf* allows plain variable bindings.
                ((symbolp place)
                 `(let ((,place ,expr))
                    ,(expand (cdr bs))))
                ;; Limited generalized variable support.
                ((and (consp place) (eq (car place) 'symbol-function) (= (length place) 2))
                 (let ((sym (gensym "SYM"))
                       (old (gensym "OLD"))
                       (new (gensym "NEW")))
                   `(let* ((,sym ,(cadr place))
                           (,old (symbol-function ,sym))
                           (,new ,expr))
                      (unwind-protect
                          (progn
                            (fset ,sym ,new)
                            ,(expand (cdr bs)))
                        (fset ,sym ,old)))))
                ((and (consp place) (eq (car place) 'symbol-value) (= (length place) 2))
                 (let ((sym (gensym "SYM"))
                       (old (gensym "OLD"))
                       (new (gensym "NEW")))
                   `(let* ((,sym ,(cadr place))
                           (,old (symbol-value ,sym))
                           (,new ,expr))
                      (unwind-protect
                          (progn
                            (set ,sym ,new)
                            ,(expand (cdr bs)))
                        (set ,sym ,old)))))
                (t
                 (cl:error "ELISP:CL-LETF* unsupported place: ~S" place)))))))
    (expand bindings)))

(cl:defparameter cl--lambda-list-keywords
  '(&optional &rest &key &allow-other-keys &aux &whole &body &environment &form
    &cl-defs)
  "Bring-up subset of cl-lib's internal `cl--lambda-list-keywords'.")

(cl:defun cl--arglist-args (lambda-list)
  "Bring-up subset of cl-lib's internal `cl--arglist-args'.

Returns a list of argument variable symbols from LAMBDA-LIST."
  (let ((out nil)
        (rest lambda-list))
    (loop while rest do
      (let ((x (pop rest)))
        (cond
         ((memq x cl--lambda-list-keywords)
          nil)
         ((symbolp x)
          (push x out))
         ((consp x)
          (let ((name (car x)))
            (when (symbolp name)
              (push name out))))
         (t nil))))
    (nreverse out)))

(cl:defun cl--find-class (name)
  "Bring-up stub for cl-lib's internal `cl--find-class'."
  (and (symbolp name) (get name 'cl--class)))

(cl:defsetf cl--find-class (name) (value)
  `(progn
     (put ,name 'cl--class ,value)
     ,value))

(cl:defun cl--make-slot-descriptor (name &optional initform type props)
  "Bring-up subset of cl-lib's internal `cl--make-slot-descriptor'.

This is used by `oclosure.el` when building its lightweight type objects.
We represent slot descriptors using the (ported) `cl-slot-descriptor' CL struct
defined in `lisp/emacs-lisp/cl-preloaded.el`."
  (make-cl-slot-descriptor :name name :initform initform :type type :props props))

(cl:defmacro cl-deftype (name args &body body)
  "Bring-up subset of cl-lib's `cl-deftype'.

This is a thin wrapper over CL:DEFTYPE so ELisp libraries that use cl-lib's
type specifiers (e.g. `oclosure.el`) can load without needing the full cl-lib
macro suite."
  `(cl:deftype ,name ,args ,@body))

(cl:defmacro cl-defstruct (&rest args)
  "Minimal subset of cl-lib's `cl-defstruct'.

Upstream cl-lib defaults to `make-<name>' constructors, like CL:DEFSTRUCT.
We only special-case SBCL quirks around (:constructor nil) combined with
named constructors."
  (let* ((spec (car args))
         (rest (cdr args))
         (doc (and rest (stringp (car rest)) (pop rest)))
         (doc* (and doc (if (cl:stringp doc) doc (%elisp-string->cl-string doc))))
         (name (if (consp spec) (car spec) spec))
         (opts (and (consp spec) (cdr spec)))
         (ctor-opts (remove-if-not (lambda (x) (and (consp x) (eq (car x) :constructor))) opts))
         (ctor-nil-p (and ctor-opts
                          (some (lambda (x) (null (cadr x))) ctor-opts)))
         (ctors (remove nil (mapcar #'cadr ctor-opts)))
         (opts* (if (and ctor-nil-p ctors)
                    ;; SBCL rejects (:constructor nil) combined with other
                    ;; constructors; cl-lib uses this to disable the default
                    ;; constructor while still defining named constructors.
                    (remove-if (lambda (x)
                                 (and (consp x) (eq (car x) :constructor) (null (cadr x))))
                               opts)
                    opts))
         (spec* (if (consp spec) (cons name opts*) spec))
         (slots*
           (mapcar
            (lambda (slot)
              ;; cl-lib sometimes includes :documentation in slot plists;
              ;; CL:DEFSTRUCT doesn't accept it, so drop it.
              (cond
               ((symbolp slot) slot)
               ((consp slot)
                (let ((nm (car slot))
                      (init (cadr slot))
                      (plist (cddr slot)))
                  (list* nm init
                         (loop for (k v) on plist by #'cddr
                               unless (eq k :documentation)
                                 append (list k v)))))
               (t slot)))
            rest))
         (args* (append (list spec*)
                        (when doc* (list doc*))
                        slots*)))
    (declare (cl:ignore name))
    `(cl:defstruct ,@args*)))

(cl:defmacro cl-defgeneric (name args &rest rest)
  "Bring-up subset of cl-generic's `cl-defgeneric'.

Defines a CLOS generic function, and (when BODY is provided) a default method."
  (unless (and (symbolp name) (listp args))
    (cl:error "ELISP:CL-DEFGENERIC expects (NAME ARGS ...), got: ~S ~S" name args))
  (let* ((doc (and rest (stringp (car rest)) (pop rest)))
         (body rest)
         (method-args
           (let ((out nil)
                 (in-keyword-section nil))
             (dolist (a args (nreverse out))
               (cond
                ((and (symbolp a)
                      (let ((nm (symbol-name a)))
                        (and (plusp (length nm))
                             (= (aref nm 0) (char-code #\&)))))
                 (setf in-keyword-section t)
                 (push a out))
                (in-keyword-section
                 (push a out))
                ((symbolp a)
                 ;; Only required args participate in CLOS dispatch.  Keep the
                 ;; rest of the lambda list (e.g. &optional) aligned with the
                 ;; generic so SBCL doesn't reject the default method.
                 (push `(,a t) out))
                (t
                 (push a out)))))))
    `(progn
       ;; Bring-up: clemacs sometimes defines small stubs for functions that
       ;; later become cl-generic generics (e.g. from `seq.el`).  SBCL rejects
       ;; DEFGENERIC when NAME already has a non-generic function definition,
       ;; so drop that placeholder to let the generic take over.
       (cl:when (and (cl:fboundp ',name)
                     (cl:not (cl:typep (cl:fdefinition ',name) 'cl:generic-function)))
         (cl:fmakunbound ',name))
       (cl:defgeneric ,name ,args
         ,@(when doc `((:documentation ,doc))))
       ,@(when body
           `((cl:defmethod ,name ,method-args
               ,@body)))
       ',name)))

(cl:defmacro cl-defmethod (name args &rest body)
  "Bring-up subset of cl-generic's `cl-defmethod'."
  (unless (and (listp args) (not (null args)))
    (cl:error "ELISP:CL-DEFMETHOD expects (NAME ARGS ...), got: ~S ~S" name args))
  (labels ((normalize-class-specializer (spec)
             ;; We shadow ELISP::STRING as a function, but ELisp cl-generic uses
             ;; the symbol `string' as a type specializer.  Rewrite to the CL
             ;; class so the underlying CLOS dispatch works.
             (cond
              ((eq spec 'string) 'cl:string)
              ((eq spec 'marker) 'elisp-marker)
              ((eq spec 'window-configuration) 'elisp-window-configuration)
              (t spec))))
    (let* ((saw-string-specializer nil)
           (method-args
             (mapcar
              (lambda (a)
                (cond
                 ((symbolp a) a)
                 ((and (consp a) (= (length a) 2) (symbolp (car a)))
                  (let ((var (car a))
                        (spec (cadr a)))
                    ;; Emacs's cl-generic treats (eql SOME-SYMBOL) as an EQL
                    ;; specializer on the symbol itself (i.e. effectively
                    ;; (eql 'SOME-SYMBOL)), not as a variable reference.
                    (cond
                     ((and (consp spec)
                           (eq (car spec) 'eql)
                           (consp (cdr spec))
                           (null (cddr spec))
                           (symbolp (cadr spec)))
                      (list var (list 'eql (list 'quote (cadr spec)))))
                     ((symbolp spec)
                      (when (eq spec 'string)
                        (setf saw-string-specializer t))
                      (list var (normalize-class-specializer spec)))
                     (t a))))
                 (t (cl:error "ELISP:CL-DEFMETHOD unsupported arg spec: ~S" a))))
              args)))
      ;; ELisp `string' specializers must match both CL strings (multibyte) and
      ;; our unibyte string representation (a specialized (unsigned-byte 8)
      ;; vector).  For the common 1-arg case, emit a second method to catch
      ;; unibyte strings.
      (if (and saw-string-specializer
               (= (length method-args) 1)
               (consp (car method-args))
               (eq (cadar method-args) 'cl:string))
          (let ((var (caar method-args)))
            `(progn
               (cl:defmethod ,name ((,var cl:string)) ,@body)
               (cl:defmethod ,name ((,var cl:vector))
                 (if (unibyte-string-p ,var)
                     (progn ,@body)
                     (call-next-method)))))
          `(cl:defmethod ,name ,method-args
             ,@body)))))

(cl:defun put (symbol prop value)
  "ELisp-ish PUT for symbol plists."
  (setf (get symbol prop) value)
  value)

(cl:defvar *elisp-function-properties* (cl:make-hash-table :test 'eq))

(cl:defun function-put (function prop value)
  "Bring-up subset of the C primitive `function-put'."
  (unless (symbolp function)
    (error "ELISP:FUNCTION-PUT expects a symbol, got: ~S" function))
  (unless (symbolp prop)
    (error "ELISP:FUNCTION-PUT expects a symbol property key, got: ~S" prop))
  (let* ((plist (gethash function *elisp-function-properties*))
         (plist* (%plist-put-preserve plist prop value)))
    (setf (gethash function *elisp-function-properties*) plist*)
    value))

(cl:defun function-get (function prop &optional default)
  "Bring-up subset of the C primitive `function-get'."
  (unless (symbolp function)
    (error "ELISP:FUNCTION-GET expects a symbol, got: ~S" function))
  (unless (symbolp prop)
    (error "ELISP:FUNCTION-GET expects a symbol property key, got: ~S" prop))
  (let ((plist (gethash function *elisp-function-properties*)))
    (loop for (k v) on plist by #'cddr do
      (when (eq k prop)
        (return v))
      finally (return default))))

(cl:defun getenv (var)
  "Bring-up subset of ELisp `getenv'."
  (unless (stringp var)
    (error "ELISP:GETENV expects a string, got: ~S" var))
  (uiop:getenv (%elisp-string->cl-string var)))

(cl:defun getenv-internal (variable &optional environment)
  "Bring-up subset of the C primitive `getenv-internal'.

VARIABLE is a string name.  ENVIRONMENT, when non-nil, is treated like an ELisp
`process-environment' list of \"NAME=VALUE\" strings."
  (unless (stringp variable)
    (error "ELISP:GETENV-INTERNAL expects a string, got: ~S" variable))
  (let* ((name (%elisp-string->cl-string variable)))
    (cond
     ((null environment)
      (uiop:getenv name))
     ((consp environment)
      (let ((prefix (concatenate 'cl:string name "=")))
        (dolist (entry environment nil)
          (when (stringp entry)
            (let ((s (%elisp-string->cl-string entry)))
              (when (and (>= (length s) (length prefix))
                         (string= prefix (subseq s 0 (length prefix))))
                (return (subseq s (length prefix)))))))))
     (t
     (error "ELISP:GETENV-INTERNAL bad ENVIRONMENT: ~S" environment)))))

(cl:defvar locale-coding-system nil)

(cl:defun decode-coding-string (string _coding-system &optional _nocopy _buffer)
  "Bring-up stub for the C primitive `decode-coding-string'.

For now, treat STRING as already decoded and return it unchanged."
  (declare (cl:ignore _coding-system _nocopy _buffer))
  (unless (stringp string)
    (error "ELISP:DECODE-CODING-STRING expects string, got: ~S" string))
  string)

(cl:defvar user-emacs-directory
  (namestring (merge-pathnames ".emacs.d/" (user-homedir-pathname))))

(cl:defun locate-user-emacs-file (new-name &optional _old-name)
  "Bring-up subset of ELisp `locate-user-emacs-file'."
  (declare (cl:ignore _old-name))
  (unless (stringp new-name)
    (error "ELISP:LOCATE-USER-EMACS-FILE expects string, got: ~S" new-name))
  (let* ((path (namestring
                (merge-pathnames (%elisp-string->cl-string new-name)
                                 user-emacs-directory))))
    ;; Emacs returns unibyte strings for ASCII-only file names.
    (if (every (lambda (ch) (< (char-code ch) 128)) path)
        (string-to-unibyte path)
        path)))

(cl:defun make-list (length init)
  "ELisp-ish MAKE-LIST."
  (unless (and (integerp length) (>= length 0))
    (error "ELISP:MAKE-LIST expects nonnegative integer length, got: ~S" length))
  (cl:make-list length :initial-element init))

(cl:defun make-string (length init)
  "ELisp-ish `make-string'.

LENGTH is the string length. INIT is an ELisp character code or a CL character."
  (unless (and (integerp length) (>= length 0))
    (error "ELISP:MAKE-STRING expects nonnegative integer length, got: ~S" length))
  (let ((code (typecase init
                (integer init)
                (character (char-code init))
                (t (error "ELISP:MAKE-STRING expects char code or character, got: ~S" init)))))
    ;; Emacs returns unibyte strings for ASCII-only output, and multibyte once
    ;; non-ASCII or raw-byte codes appear.
    (if (and (integerp code) (<= 0 code 127))
        (%make-unibyte-string length :initial-element code)
        (let ((ch (%elisp-code->char code)))
          (cl:make-string length :initial-element ch)))))

(defvar *charset-aliases* (cl:make-hash-table :test 'eq))

(cl:defvar char-code-property-alist nil)

(cl:defun get-char-code-property (char propname)
  "Bring-up stub for ELisp `get-char-code-property'.

This will eventually consult the Unicode property tables (as in Emacs'
`charprop.el').  For bring-up, return nil for unknown properties so callers
can load without requiring the full Unicode database."
  (unless (integerp char)
    (error "ELISP:GET-CHAR-CODE-PROPERTY expects integer char code, got: ~S" char))
  (unless (symbolp propname)
    (error "ELISP:GET-CHAR-CODE-PROPERTY expects symbol property, got: ~S" propname))
  nil)

(cl:defun define-char-code-property (name file &optional docstring)
  "Bring-up stub for ELisp `define-char-code-property'.

Record NAME as a known char-code property, and remember its data FILE and
DOCSTRING (optional).  The actual property tables are loaded lazily by upstream
code; for bring-up we only need registration to succeed so
`international/charprop.el' and `international/ucs-normalize.el' can be loaded."
  (unless (symbolp name)
    (error "ELISP:DEFINE-CHAR-CODE-PROPERTY expects a symbol, got: ~S" name))
  (unless (stringp file)
    (error "ELISP:DEFINE-CHAR-CODE-PROPERTY expects a string file, got: ~S" file))
  (unless (or (null docstring) (stringp docstring))
    (error "ELISP:DEFINE-CHAR-CODE-PROPERTY expects a docstring or nil, got: ~S" docstring))
  (put name 'char-code-property t)
  (put name 'char-code-property-file file)
  (when docstring
    (put name 'char-code-property-doc docstring))
  (unless (assq name char-code-property-alist)
    (push (cons name nil) char-code-property-alist))
  name)

(cl:defvar *defined-categories* (cl:make-hash-table :test 'eql))

(cl:defun define-category (category docstring)
  "Bring-up stub for ELisp `define-category'.

Emacs uses category tables for syntax/category classification of characters.
For bring-up we only record the category definitions so that
`international/characters.el` can be loaded."
  (unless (integerp category)
    (error "ELISP:DEFINE-CATEGORY expects a character code integer, got: ~S" category))
  (unless (stringp docstring)
    (error "ELISP:DEFINE-CATEGORY expects a docstring, got: ~S" docstring))
  (setf (gethash category *defined-categories*) docstring)
  category)

(cl:defun define-charset-alias (alias charset)
  "Bring-up stub for ELisp `define-charset-alias'."
  (unless (and (symbolp alias) (symbolp charset))
    (error "ELISP:DEFINE-CHARSET-ALIAS expects symbols, got: ~S ~S" alias charset))
  (setf (gethash alias *charset-aliases*) charset)
  alias)

(cl:defun %resolve-charset (sym &key (max-hops 16))
  (loop with cur = sym
        for hop from 0 below max-hops do
          (multiple-value-bind (next presentp)
              (gethash cur *charset-aliases*)
            (cond
             ((not presentp) (return cur))
             ((not (symbolp next)) (return cur))
             (t (setf cur next))))
        finally
          (return sym)))

(cl:defun charset-plist (charset)
  "Bring-up subset of the C primitive `charset-plist'."
  (unless (symbolp charset)
    (error "ELISP:CHARSET-PLIST expects a symbol, got: ~S" charset))
  (symbol-plist (%resolve-charset charset)))

(cl:defun set-charset-plist (charset plist)
  "Bring-up subset of the internal helper `set-charset-plist'."
  (unless (symbolp charset)
    (error "ELISP:SET-CHARSET-PLIST expects a symbol, got: ~S" charset))
  (setf (symbol-plist (%resolve-charset charset)) plist)
  plist)

(cl:defun define-charset-internal (name &rest attrs)
  "Bring-up stub for the C primitive `define-charset-internal'."
  (unless (symbolp name)
    (error "ELISP:DEFINE-CHARSET-INTERNAL expects symbol, got: ~S" name))
  (let ((plist (car (last attrs))))
    (when (listp plist)
      (set-charset-plist name plist))
    (put name 'charsetp t)
    name))

(cl:defun put-charset-property (charset prop value)
  "Bring-up stub for ELisp `put-charset-property'."
  (unless (and (symbolp charset) (symbolp prop))
    (error "ELISP:PUT-CHARSET-PROPERTY expects symbols, got: ~S ~S" charset prop))
  (put (%resolve-charset charset) prop value))

(cl:defun unify-charset (charset)
  "Bring-up stub for the C primitive `unify-charset'."
  (unless (symbolp charset)
    (error "ELISP:UNIFY-CHARSET expects a symbol, got: ~S" charset))
  charset)

(cl:defun define-charset (name _docstring &rest plist)
  "Bring-up stub for ELisp `define-charset'.

We currently represent charsets as symbols with properties."
  (declare (cl:ignore _docstring))
  (unless (symbolp name)
    (error "ELISP:DEFINE-CHARSET expects symbol, got: ~S" name))
  (put name 'charsetp t)
  (when (cl:oddp (length plist))
    (error "ELISP:DEFINE-CHARSET odd keyword args: ~S" plist))
  (loop for (k v) on plist by (cl:function cl:cddr) do
    (put name k v))
  name)
