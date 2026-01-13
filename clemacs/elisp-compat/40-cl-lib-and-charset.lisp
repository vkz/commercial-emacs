(in-package #:elisp)

(cl:defmacro cl-progv (symbols values &body body)
  "Bring-up subset of cl-lib's `cl-progv'."
  (labels ((quoted-symbol-list (x)
             (when (and (consp x) (eq (car x) 'quote)
                        (consp (cdr x)) (null (cddr x))
                        (listp (cadr x)))
               (let* ((raw (cadr x))
                      (syms (remove-if-not #'symbolp raw)))
                 (remove-if (lambda (s) (cl:member s '(nil t) :test #'eq)) syms)))))
    (let ((specials (quoted-symbol-list symbols)))
      (if specials
          `(cl:progv ,symbols ,values
             (locally (declare (special ,@specials))
               ,@body))
          `(cl:progv ,symbols ,values ,@body)))))

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

(cl:defmacro cl-macrolet (bindings &body body &environment _env0)
  "Bring-up subset of cl-lib's `cl-macrolet'.

ERT's `should' macro calls `macroexpand-all' and passes
`macroexpand-all-environment'.  In Emacs, `cl-macrolet' extends that
environment with its locally-bound macros.

In clemacs, `macroexpand-all-environment' is an Emacs-style macro env alist
(as expected by `lisp/emacs-lisp/macroexp.el').  Extend that env and fully
macroexpand BODY so locally-defined macros are expanded inside the expansions
of other macros (bug#46786 / `pcase-tests-bug46786')."
  (declare (cl:ignore _env0))
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
                        `(cl:function
                          (lambda ,lambda-list
                            ,body-form))))))))))
    (let* ((macroexpanders (mapcar (lambda (binding)
                                    (let ((m (binding->macro binding)))
                                      (cons (car m) (cadr m))))
                                  bindings))
           (outer-env (if (listp macroexpand-all-environment)
                          macroexpand-all-environment
                          nil))
           (env1 (append macroexpanders outer-env)))
      (let ((macroexpand-all-environment env1))
        (declare (special macroexpand-all-environment))
        ;; Prefer the clemacs-compatible `macroexpand-all' saved during core
        ;; bring-up: upstream `macroexpand-all' can be loaded later and will
        ;; overwrite the global function name.
        (let ((body-form (macroexp-progn body)))
          (cond
           ((and (boundp '*macroexpand-all-compat*) *macroexpand-all-compat*)
            (funcall *macroexpand-all-compat* body-form env1))
           (t
            (macroexpand-all body-form env1))))))))

(cl:defmacro cl-flet (bindings &body body)
  "Bring-up subset of cl-lib's `cl-flet'.

Supports both normal local function bindings:
  ((NAME (ARGLIST...) BODY...) ...)
and cl-lib's alias shorthand:
  ((NAME TARGET) ...)
where TARGET evaluates to a callable object."
  (let ((alias-lets nil)
        (out-bindings nil))
    (dolist (b bindings)
      (unless (and (consp b) (symbolp (car b)))
        (error "ELISP:CL-FLET invalid binding: %S" b))
      (let ((name (car b))
            (rest (cdr b)))
        (cond
         ;; Alias shorthand: (NAME TARGET)
         ((and (consp rest) (null (cdr rest)) (not (listp (car rest))))
          (let ((fn-var (cl:gensym "CL-FLET-FN-")))
            (push (list fn-var (car rest)) alias-lets)
            (push (list name '(&rest args) `(apply ,fn-var args)) out-bindings)))
         ;; Normal definition: (NAME (ARGLIST...) BODY...)
         ((and (consp rest) (listp (car rest)))
          (push b out-bindings))
         (t
          (error "ELISP:CL-FLET invalid binding: %S" b)))))
    (let ((out-bindings (nreverse out-bindings))
          (alias-lets (nreverse alias-lets)))
      (if alias-lets
          `(let ,alias-lets (cl:flet ,out-bindings ,@body))
          `(cl:flet ,out-bindings ,@body)))))

(cl:defmacro cl-function (fn)
  "Bring-up subset of cl-lib's `cl-function'.

Upstream uses this macro to add Common Lisp-ish lambda-list support (e.g. &key).
For clemacs bring-up we only need `cl-generic` to be able to macroexpand away
the `cl-function` wrapper around a plain `lambda`."
  `(function ,fn))

(cl:defmacro cl-labels (bindings &body body)
  "Bring-up subset of cl-lib's `cl-labels'.

Supports both normal local function bindings:
  ((NAME (ARGLIST...) BODY...) ...)
and cl-lib's alias shorthand:
  ((NAME TARGET) ...)
where TARGET evaluates to a callable object."
  (let ((alias-lets nil)
        (out-bindings nil))
    (dolist (b bindings)
      (unless (and (consp b) (symbolp (car b)))
        (error "ELISP:CL-LABELS invalid binding: %S" b))
      (let ((name (car b))
            (rest (cdr b)))
        (cond
         ((and (consp rest) (null (cdr rest)) (not (listp (car rest))))
          (let ((fn-var (cl:gensym "CL-LABELS-FN-")))
            (push (list fn-var (car rest)) alias-lets)
            (push (list name '(&rest args) `(apply ,fn-var args)) out-bindings)))
         ((and (consp rest) (listp (car rest)))
          (push b out-bindings))
         (t
          (error "ELISP:CL-LABELS invalid binding: %S" b)))))
    (let ((out-bindings (nreverse out-bindings))
          (alias-lets (nreverse alias-lets)))
      (if alias-lets
          `(let ,alias-lets (cl:labels ,out-bindings ,@body))
          `(cl:labels ,out-bindings ,@body)))))

(cl:defun cl-adjoin (item list &rest keys)
  "Bring-up subset of cl-lib's `cl-adjoin'."
  (apply #'cl:adjoin item list keys))

(cl:defun cl-reduce (function sequence &rest keys)
  "Bring-up subset of cl-lib's `cl-reduce'."
  (apply #'cl:reduce function sequence keys))

(cl:defun cl-some (predicate sequence &rest sequences)
  "Bring-up subset of cl-lib's `cl-some'."
  (let ((result nil)
        (foundp nil))
    (apply #'mapc
           (lambda (&rest args)
             (unless foundp
               (let ((v (apply #'funcall predicate args)))
                 (when v
                   (setf result v
                         foundp t)))))
           sequence
           sequences)
    result))

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
           (rewrite-below (xs)
             ;; SBCL's CL:LOOP expansion emits a non-standard internal type
             ;; specifier for `for VAR below ...` with an implicit start of 0:
             ;;   (declare (type (if number real) var))
             ;; which later trips runtime type checks.  Normalize to the
             ;; explicit CL spelling so SBCL uses a standard type:
             ;;   for VAR from 0 below ...
             (let ((out nil)
                   (rest xs))
               (loop while rest do
                 (cond
                  ((and (consp rest)
                        (cl:member (car rest) '(for as) :test #'eq)
                        (consp (cdr rest))
                        (symbolp (cadr rest))
                        (consp (cddr rest))
                        (eq (caddr rest) 'below)
                        (consp (cdddr rest)))
                   (let ((kw (car rest))
                         (var (cadr rest))
                         (limit (cadddr rest)))
                     (push kw out)
                     (push var out)
                     (push 'from out)
                     (push 0 out)
                     (push 'below out)
                     (push limit out)
                     (setf rest (cddddr rest))))
                  (t
                   (push (car rest) out)
                   (setf rest (cdr rest)))))
               (nreverse out)))
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
      (setf clauses* (rewrite-below clauses*))
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
  (labels ((type-op-p (op name)
             (and (symbolp op)
                  (cl:string-equal (cl:symbol-name op) name))))
    (cond
     ((and (consp type) (type-op-p (car type) "IF") (= (length type) 3))
      ;; cl-lib sometimes uses a 2-branch conditional type:
      ;;   (if COND THEN)
      ;; Treat the implicit ELSE as T: values not matching COND are accepted.
      (if (cl-typep object (cadr type))
          (cl-typep object (caddr type))
        t))
     ((and (consp type) (type-op-p (car type) "IF") (= (length type) 4))
      ;; cl-lib's extended type specifier:
      ;;   (if COND THEN ELSE)
      ;; Interpret this as: if OBJECT matches COND, then require THEN, else ELSE.
      (if (cl-typep object (cadr type))
          (cl-typep object (caddr type))
        (cl-typep object (cadddr type))))
     ((and (consp type) (type-op-p (car type) "SATISFIES") (= (length type) 2))
      (funcall (cadr type) object))
     ((and (consp type) (type-op-p (car type) "MEMBER"))
      ;; In Emacs, `cl-typep' treats MEMBER tests as `equal' comparisons (so it
      ;; works on lists/vectors/strings), rather than CL's EQL-based member type.
      (and (member object (cdr type)) t))
     (t
      (cl:typep object type)))))

(cl:defun typep (object type)
  "Bring-up subset of cl-lib's `typep'.

Unlike CL:TYPEP, this accepts cl-lib's extended type specifiers (e.g. (if ...))
and treats (member ...) as an `equal'-based membership test."
  (cl-typep object type))

(pcase-defmacro cl-type (type)
  "Pcase pattern that matches objects of TYPE.
TYPE is a type descriptor as accepted by `cl-typep', which see."
  `(pred (cl-typep _ ',type)))

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

(cl:defmacro cl-dolist (spec &body body)
  "Minimal subset of cl-lib's `cl-dolist'."
  (destructuring-bind (var listform &optional result) spec
    `(cl:dolist (,var ,listform ,result)
       ,@body)))

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

(cl:defvar cl--gensym-counter 0)

(cl:defun cl-gensym (&optional prefix)
  "Bring-up subset of cl-lib's `cl-gensym'."
  (let* ((p (cond
             ((null prefix) "G")
             ((stringp prefix) prefix)
             ((symbolp prefix) (symbol-name prefix))
             (t (cl:error "ELISP:CL-GENSYM unsupported prefix: ~S" prefix))))
         (p* (%elisp-string->cl-string p))
         (n cl--gensym-counter)
         (nm (cl:format nil "~A~D" p* n)))
    (setf cl--gensym-counter (1+ cl--gensym-counter))
    (make-symbol nm)))

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

(cl:defun cl-subseq (seq start &optional end)
  "Bring-up subset of cl-extra's `cl-subseq'.

Upstream `cl-subseq' is implemented in terms of `seq-subseq'."
  (unless (fboundp 'seq-subseq)
    (error "ELISP:CL-SUBSEQ requires SEQ (missing SEQ-SUBSEQ)"))
  (seq-subseq seq start end))

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

(cl:defstruct (clemacs--builtin-class
               (:constructor %make-clemacs--builtin-class (name))
               (:copier nil))
  name)

(cl:defvar *clemacs--builtin-classes* (cl:make-hash-table :test 'eq))

(cl:defun %clemacs--builtin-class (name)
  (multiple-value-bind (v presentp)
      (gethash name *clemacs--builtin-classes*)
    (if presentp
        v
        (setf (gethash name *clemacs--builtin-classes*)
              (%make-clemacs--builtin-class name)))))

(cl:defun %clemacs--builtin-type-name-p (name)
  ;; Start small and extend as needed while bringing up `cl-generic'.
  (memq name
        '(symbol cons integer string vector hash-table char-table
          number marker window-configuration registerv
          cl--generic-generalizer oclosure)))

(cl:defun cl--find-class (name)
  "Bring-up stub for cl-lib's internal `cl--find-class'."
  (unless (symbolp name)
    (return-from cl--find-class nil))
  (or (get name 'cl--class)
      ;; Prefer the host class when available.  This allows cl-generic's
      ;; "typeof" generalizer to work for CL built-in types (e.g. FLOAT) and
      ;; CL structs defined via our `cl-defstruct' wrapper.
      (ignore-errors (cl:find-class name nil))
      (and (%clemacs--builtin-type-name-p name)
           (%clemacs--builtin-class name))))

(cl:defsetf cl--find-class (name) (value)
  `(progn
     (put ,name 'cl--class ,value)
     ,value))

(cl:defun cl--class-allparents (class)
  "Bring-up subset of cl-lib's internal `cl--class-allparents'."
  (cond
   ((typep class 'clemacs--builtin-class)
    (list (clemacs--builtin-class-name class) t))
   #+sbcl
   ((typep class 'cl:class)
    (remove nil (mapcar #'cl:class-name (sb-mop:class-precedence-list class))))
   (t
    (list (type-of class) t))))

(cl:defun cl-type-of (object)
  "Bring-up subset of cl-lib's `cl-type-of'.

This returns an Emacs-ish type symbol suitable for cl-generic dispatch tags."
  (cond
   ((typep object 'elisp-char-table) 'char-table)
   ((typep object 'elisp-marker) 'marker)
   ((typep object 'elisp-window-configuration) 'window-configuration)
   (t
    #+sbcl
    (let ((c (cl:class-of object)))
      (or (and (typep c 'cl:class) (cl:class-name c))
          (cl:type-of object)))
    #-sbcl
    (cl:type-of object))))

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

(cl:defmacro cl-callf (fun place &rest args)
  "Bring-up subset of cl-lib's `cl-callf'."
  ;; In ELisp, symbols in "function position" are resolved via the function cell.
  ;; `cl-callf' is used like: (cl-callf + place ...).  The function designator
  ;; must therefore be passed as a symbol, not evaluated as a variable.
  (let ((fun* (if (symbolp fun) `',fun fun)))
    `(setf ,place (funcall ,fun* ,place ,@args))))

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
         (ctor-doc-forms nil)
         (opts
           (and (consp spec)
                (mapcar
                 (lambda (opt)
                   (if (and (consp opt) (eq (car opt) :constructor))
                       (cl:destructuring-bind
                           (_kw &optional ctor-name ctor-lambda ctor-doc &rest _rest)
                           opt
                         (declare (cl:ignore _kw _rest))
                         (when (and (symbolp ctor-name) ctor-doc)
                           (let ((ctor-doc*
                                   (if (cl:stringp ctor-doc)
                                       ctor-doc
                                       (%elisp-string->cl-string ctor-doc))))
                             (push `(setf (cl:documentation ',ctor-name 'cl:function)
                                          ,ctor-doc*)
                                   ctor-doc-forms)))
                         ;; SBCL's CL:DEFSTRUCT doesn't accept constructor
                         ;; docstrings (cl-lib does), so strip them here and
                         ;; reattach via CL:DOCUMENTATION above.
                         (cond
                          ((null ctor-name) '(:constructor nil))
                          ((null ctor-lambda) (list :constructor ctor-name))
                          (t (list :constructor ctor-name ctor-lambda))))
                       opt))
                 (cdr spec))))
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
              ;; CL:DEFSTRUCT doesn't accept it, so drop it.  Also drop :type
              ;; constraints: upstream cl-lib uses them for documentation / hints,
              ;; and SBCL may enforce them at runtime (which can break bring-up
              ;; code that stores symbols where cl-lib wrote :type string).
              (cond
               ((symbolp slot) slot)
               ((consp slot)
                (let ((nm (car slot))
                       (init (cadr slot))
                      (plist (cddr slot)))
                  (list* nm init
                         (loop for (k v) on plist by #'cddr
                               unless (or (eq k :documentation) (eq k :type))
                                 append (list (if (eq k :readonly) :read-only k) v)))))
               (t slot)))
            rest))
         (args* (append (list spec*)
                        (when doc* (list doc*))
                        slots*)))
    (declare (cl:ignore name))
    `(progn
       (cl:defstruct ,@args*)
       ,@(nreverse ctor-doc-forms)
       ',name)))

(cl:defmacro cl-defgeneric (name args &rest rest)
  "Bring-up subset of cl-generic's `cl-defgeneric'.

Defines a CLOS generic function, and (when BODY is provided) a default method."
  (labels ((setf-name-p (x)
             (and (consp x)
                  (eq (car x) 'setf)
                  (consp (cdr x))
                  (symbolp (cadr x))
                  (null (cddr x)))))
    (unless (and (or (symbolp name) (setf-name-p name)) (listp args))
      (cl:error "ELISP:CL-DEFGENERIC expects NAME (or (setf NAME)) and ARGS, got: ~S ~S"
                name args)))
  (let* ((doc (and rest (stringp (car rest)) (pop rest)))
         (decl-forms nil))
    (labels ((declare-form-p (x)
               (and (consp x)
                    (symbolp (car x))
                    (cl:string-equal "DECLARE" (cl:symbol-name (car x))))))
      (loop while (and rest (declare-form-p (car rest))) do
        (push (pop rest) decl-forms)))
    (setf decl-forms (nreverse decl-forms))
    (let* ((decl-items (mapcan #'cdr decl-forms))
           (gv-expander nil)
           (advertised-cc nil)
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
      (dolist (decl decl-items)
        (when (and (consp decl) (symbolp (car decl)))
          (let ((nm (cl:symbol-name (car decl))))
            (cond
             ((cl:string-equal nm "GV-EXPANDER")
              (when (and (consp (cdr decl)) (null (cddr decl)))
                (setf gv-expander (cadr decl))))
             ((cl:string-equal nm "ADVERTISED-CALLING-CONVENTION")
              (when (and (consp (cdr decl)) (listp (cadr decl)))
                (setf advertised-cc (cadr decl))))))))
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
         ,@(when gv-expander
             `((function-put ',name 'gv-expander ,gv-expander)))
         ,@(when advertised-cc
             `((set-advertised-calling-convention ',name ',advertised-cc)))
         ,@(when body
             `((cl:defmethod ,name ,method-args
                 ,@body)))
         ',name))))

(cl:defmacro cl-defmethod (name args &rest body)
  "Bring-up subset of cl-generic's `cl-defmethod'."
  (unless (and (listp args) (not (null args)))
    (cl:error "ELISP:CL-DEFMETHOD expects (NAME ARGS ...), got: ~S ~S" name args))
  (labels ((&context-marker-p (x)
             (and (symbolp x)
                  (cl:string-equal "&context" (cl:symbol-name x))))
           (strip-&context (lambda-list)
             ;; cl-generic extends `cl-defmethod' with `&context' pseudo-args
             ;; used for dispatching on dynamic "contexts" like `window-system'.
             ;;
             ;; clemacs does not implement context dispatch yet.  For bring-up,
             ;; drop `&context' and everything after it, so core files like
             ;; `frame.el` can load.
             (let ((out nil)
                   (rest lambda-list))
               (loop while rest do
                 (let ((a (pop rest)))
                   (when (&context-marker-p a)
                     (return (nreverse out)))
                   (push a out)))
               (nreverse out)))
           (normalize-class-specializer (spec)
             ;; We shadow ELISP::STRING as a function, but ELisp cl-generic uses
             ;; the symbol `string' as a type specializer.  Rewrite to the CL
             ;; class so the underlying CLOS dispatch works.
             (cond
              ((eq spec 'string) 'cl:string)
              ((eq spec 'marker) 'elisp-marker)
              ((eq spec 'window-configuration) 'elisp-window-configuration)
              (t spec))))
    (let* ((args (strip-&context args))
           (saw-string-specializer nil)
           (head-guards nil)
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
                     ;; cl-generic `(head SYMBOL)` specializer: dispatch on the
                     ;; head of a cons cell (used heavily by `map.el`).
                     ;;
                     ;; We approximate it by specializing on CONS and using a
                     ;; runtime guard to fall through to the next method.
                     ((and (consp spec)
                           (eq (car spec) 'head)
                           (consp (cdr spec))
                           (null (cddr spec))
                           (symbolp (cadr spec)))
                      (push `(eq (car ,var) ',(cadr spec)) head-guards)
                      (list var 'cl:cons))
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
      (when head-guards
        (setf body
              `((if (and ,@(nreverse head-guards))
                    (progn ,@body)
                    (call-next-method)))))
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

(cl:defmacro cl-call-next-method (&rest args)
  "Bring-up subset of cl-lib's `cl-call-next-method'."
  `(call-next-method ,@args))

(cl:defun put (symbol prop value)
  "ELisp-ish PUT for symbol plists."
  ;; CL's (setf (get ...)) prepends new properties; Emacs preserves insertion
  ;; order (and updates in place) on symbol plists.
  (setf (symbol-plist symbol)
        (%plist-put-preserve (symbol-plist symbol) prop value))
  value)

(cl:defun function-put (function prop value)
  "Bring-up subset of the C primitive `function-put'.

Emacs stores function properties on the function symbol's plist (shared with
symbol properties).  clemacs follows that behavior so upstream `byte-run.el'
aliases (e.g. `function-put' -> `put') remain compatible."
  (unless (symbolp function)
    (error "ELISP:FUNCTION-PUT expects a symbol, got: ~S" function))
  (unless (symbolp prop)
    (error "ELISP:FUNCTION-PUT expects a symbol property key, got: ~S" prop))
  (put function prop value))

(cl:defun function-get (f prop &optional autoload)
  "Bring-up subset of the C primitive `function-get'.

This matches the shape of Emacs's implementation in `lisp/subr.el`: follow
function indirections while looking for PROP on the symbol plist.  When
AUTOLOAD is non-nil and F is an autoload, attempt to load it."
  (unless (symbolp f)
    (error "ELISP:FUNCTION-GET expects a symbol, got: ~S" f))
  (unless (symbolp prop)
    (error "ELISP:FUNCTION-GET expects a symbol property key, got: ~S" prop))
  (let ((val nil)
        (cur f)
        (seen nil))
    (loop
      (when (not (symbolp cur))
        (return val))
      ;; Avoid infinite loops on circular function indirections like:
      ;; (fset 'a 'b) (fset 'b 'a)
      (when (cl:member cur seen :test #'eq)
        (return nil))
      (push cur seen)
      (setf val (get cur prop))
      (when val
        (return val))
      (unless (fboundp cur)
        (return nil))
      (let ((fundef (symbol-function cur)))
        (cond
         ((and autoload (consp fundef) (eq (car fundef) 'autoload)
               (or (not (eq autoload 'macro))
                   (and (consp (cdr fundef)) (eq (cadr fundef) 'macro))))
          (let ((loaded (autoload-do-load fundef cur (and (eq autoload 'macro) 'macro))))
            (when (not (equal loaded fundef))
              (setf fundef loaded))))
         (t nil))
        (setf cur fundef)))))

(cl:defun getenv (var &optional _frame)
  "Bring-up subset of ELisp `getenv'."
  (declare (cl:ignore _frame))
  (getenv-internal var nil))

(cl:defun getenv-internal (variable &optional environment)
  "Bring-up subset of the C primitive `getenv-internal'.

VARIABLE is a string name.  ENVIRONMENT, when non-nil, is treated like an ELisp
`process-environment' list of \"NAME=VALUE\" strings."
  (unless (stringp variable)
    (error "ELISP:GETENV-INTERNAL expects a string, got: ~S" variable))
  (let* ((name (%elisp-string->cl-string variable))
         (env (cond
               ((null environment) process-environment)
               ((consp environment) environment)
               (t (error "ELISP:GETENV-INTERNAL bad ENVIRONMENT: ~S" environment))))
         (prefix (concatenate 'cl:string name "=")))
    (dolist (entry env nil)
      (when (stringp entry)
        (let ((s (%elisp-string->cl-string entry)))
          (cond
           ;; NAME=VALUE
           ((and (>= (length s) (length prefix))
                 (string= prefix (subseq s 0 (length prefix))))
            (return (subseq s (length prefix))))
           ;; NAME (unset marker; `setenv` uses this on unsetting)
           ((string= name s)
            (return nil))))))))

(cl:defun setenv-internal (env variable value keep-empty)
  "Set VARIABLE to VALUE in ENV, adding empty entries if KEEP-EMPTY.

ENV is an ELisp `process-environment` list of strings.  VALUE is either a
string (including \"\"), or nil to unset.  KEEP-EMPTY matches upstream: unsets
leave a \"NAME\" marker in ENV instead of deleting the entry."
  (unless (stringp variable)
    (error "ELISP:SETENV-INTERNAL expects VARIABLE string, got: ~S" variable))
  (when (and value (not (stringp value)))
    (error "ELISP:SETENV-INTERNAL expects VALUE string or nil, got: ~S" value))
  (let* ((name (%elisp-string->cl-string variable))
         (val (and value (%elisp-string->cl-string value)))
         (found nil))
    (labels ((entry-matches-p (entry)
               (and (stringp entry)
                    (let ((s (%elisp-string->cl-string entry)))
                      (or (string= s name)
                          (and (>= (length s) (1+ (length name)))
                               (string= name (subseq s 0 (length name)))
                               (char= #\= (char s (length name))))))))
             (make-entry ()
               (cond
                (val (concatenate 'cl:string name "=" val))
                (keep-empty name)
                (t nil))))
      (let ((new-entry (make-entry))
            (out nil))
        (dolist (entry env)
          (if (and (not found) (entry-matches-p entry))
              (progn
                (setf found t)
                (when new-entry
                  (push new-entry out)))
              (push entry out)))
        (setf out (nreverse out))
        (if found
            out
            (if new-entry
                (cons new-entry env)
                env))))))

(cl:defun setenv (variable &optional value substitute-env-vars)
  "Set VARIABLE to VALUE in `process-environment` (bring-up subset)."
  (unless (stringp variable)
    (error "ELISP:SETENV expects VARIABLE string, got: ~S" variable))
  (when (and value (not (stringp value)))
    (error "ELISP:SETENV expects VALUE string or nil, got: ~S" value))
  (when (position #\= (%elisp-string->cl-string variable))
    (error "Environment variable name `%s' contains `='" variable))
  (when (and value substitute-env-vars (fboundp 'substitute-env-vars))
    (setf value (substitute-env-vars value)))
  (when (string= "TZ" (%elisp-string->cl-string variable))
    (set-time-zone-rule value))
  (setf process-environment
        (setenv-internal process-environment variable value t))
  value)

(cl:defvar locale-coding-system nil)

(cl:defun find-coding-systems-string (_string &optional _default-coding)
  "Bring-up stub for the C primitive `find-coding-systems-string'."
  (declare (cl:ignore _string _default-coding))
  (list 'undecided))

(cl:defun coding-system-base (coding-system)
  "Bring-up stub for the C primitive `coding-system-base'."
  coding-system)

(cl:defun set-time-zone-rule (&optional _rules)
  "Bring-up stub for the C primitive `set-time-zone-rule'."
  (declare (cl:ignore _rules))
  nil)

(cl:defvar current-language-environment "English")
(cl:defvar selection-coding-system nil)
(cl:defvar terminal-coding-system nil)

(cl:defun coding-system-p (object)
  "Bring-up stub for the C primitive `coding-system-p'."
  ;; Emacs treats nil as a valid coding system (meaning: use defaults).
  (or (null object)
      (and (symbolp object) (not (eq object t)) t)))

(cl:defun display-graphic-p (&optional _frame)
  "Bring-up stub for the C primitive `display-graphic-p'."
  (declare (cl:ignore _frame))
  nil)

(cl:defun terminal-coding-system (&optional _terminal)
  "Bring-up subset of ELisp `terminal-coding-system'."
  (declare (cl:ignore _terminal))
  terminal-coding-system)

(cl:defun set-terminal-coding-system (coding-system &optional _terminal)
  "Bring-up subset of ELisp `set-terminal-coding-system'."
  (declare (cl:ignore _terminal))
  (setf terminal-coding-system coding-system)
  coding-system)

(cl:defun set-selection-coding-system (coding-system &optional _terminal)
  "Bring-up subset of ELisp `set-selection-coding-system'."
  (declare (cl:ignore _terminal))
  (setf selection-coding-system coding-system)
  coding-system)

(cl:defun prefer-coding-system (coding-system)
  "Bring-up subset of ELisp `prefer-coding-system'."
  (setf locale-coding-system coding-system)
  coding-system)

(cl:defun set-locale-environment (locale)
  "Bring-up stub for ELisp `set-locale-environment'."
  (setf system-time-locale locale)
  locale)

(cl:defun set-language-environment (language)
  "Bring-up subset of ELisp `set-language-environment'."
  (setf current-language-environment language)
  language)

(cl:defun standard-display-european-internal (&rest _args)
  "Bring-up stub for ELisp `standard-display-european-internal'."
  (declare (cl:ignore _args))
  nil)

(cl:defun unibyte-char-to-multibyte (char)
  "Bring-up subset of ELisp `unibyte-char-to-multibyte'."
  (unless (integerp char)
    (error "ELISP:UNIBYTE-CHAR-TO-MULTIBYTE expects an integer char code, got: ~S" char))
  (unless (<= 0 char 255)
    (error "ELISP:UNIBYTE-CHAR-TO-MULTIBYTE expects 0..255, got: ~S" char))
  (if (<= char 127)
      char
      (+ #x3FFF00 char)))

(cl:defun max-char (&optional charset)
  "Bring-up subset of the C primitive `max-char'."
  (cond
   ((null charset) #x3FFFFF)
   (t #x10FFFF)))

(cl:defun char-displayable-p (char &optional _display)
  "Bring-up subset of ELisp `char-displayable-p'."
  (declare (cl:ignore _display))
  (let ((code (typecase char
                (integer char)
                (character (char-code char))
                (t (return-from char-displayable-p nil)))))
    (and (<= 0 code (max-char 'unicode))
         ;; Treat NUL and other control chars as non-displayable.
         (or (>= code 32) (member code '(9 10 13)))
         t)))

(cl:defvar system-time-locale nil)

(cl:defvar init-file-user nil)

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
  (case propname
    ;; `ucs-normalize.el` expects a numeric canonical combining class, and will
    ;; sort lists of chars using `<` on that value.  Returning NIL here breaks
    ;; the sort comparator with `(wrong-type-argument number-or-marker-p nil)`.
    ;; For bring-up, treat all chars as having CCC=0.
    (canonical-combining-class 0)
    (t nil)))

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

(defvar input-method-alist nil
  "Alist of input method names vs how to use them.
Each element has the form:
  (INPUT-METHOD LANGUAGE-ENV ACTIVATE-FUNC TITLE DESCRIPTION ARGS...)")

(cl:defun register-input-method (input-method lang-env &rest args)
  "Register INPUT-METHOD as an input method for language environment LANG-ENV.

Bring-up implementation, matching Emacs's mule-cmds.el semantics."
  (let* ((lang-env (if (symbolp lang-env) (symbol-name lang-env) lang-env))
         (input-method (if (symbolp input-method)
                           (symbol-name input-method)
                           input-method))
         (info (cons lang-env args))
         (slot (assoc input-method input-method-alist)))
    (if slot
        (setcdr slot info)
        (progn
          (setf slot (cons input-method info))
          (setf input-method-alist (cons slot input-method-alist))))
    input-method-alist))
