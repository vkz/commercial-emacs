(in-package #:elisp)

;; ---------------------------------------------------------------------------
;; Minimal pcase subset (bring-up)
;;
;; Goal: support the common `pcase-dolist' destructuring patterns used across
;; the shipped ELisp tree, without pulling in the full upstream `pcase.el'
;; machinery yet.
;;
;; This is intentionally a subset. The plan is to eventually load and run the
;; upstream `lisp/emacs-lisp/pcase.el' implementation under clemacs, at which
;; point these stubs should become unused/overridden.
;; ---------------------------------------------------------------------------

(cl:defvar *pcase--pattern-macroexpanders*
  (cl:make-hash-table :test #'eq))

(cl:defun %pcase--get-pattern-macroexpander (sym)
  (gethash sym *pcase--pattern-macroexpanders*))

(cl:defmacro pcase-defmacro (name args &rest body)
  "Bring-up subset of ELisp `pcase-defmacro'.

This defines a pattern-macro expander for patterns of the form (NAME ...).

For bring-up, we register the expander in two places:
- `*pcase--pattern-macroexpanders*' for the early CL-side `pcase' subset.
- The `pcase-macroexpander' symbol property, so upstream `pcase.el' (when
  loaded later) can reuse expanders that were defined earlier (notably
  `cl-macs.el' defines the `cl-type' pattern before `pcase.el' is loaded)."
  (let ((doc-form
          (and body
               (or (cl:stringp (car body)) (cl:vectorp (car body)))
               (car body)))
        (decl (and body (consp (car body)) (eq (caar body) 'declare) (car body))))
    (when doc-form (setf body (cdr body)))
    (when decl (setf body (cdr body)))
    (let* ((elisp-pkg (cl:find-package "ELISP"))
           (fsym (cl:intern (cl:format nil "~A--PCASE-MACROEXPANDER"
                                       (cl:symbol-name name))
                            elisp-pkg))
           (doc-string (and doc-form (cl:stringp doc-form) doc-form)))
      `(eval-when (:compile-toplevel :load-toplevel :execute)
         (cl:defun ,fsym ,args
           ,@(when doc-string (list doc-string))
           ,@body)
         (setf (gethash ',name *pcase--pattern-macroexpanders*) #',fsym)
         (setf (get ',name 'pcase-macroexpander) #',fsym)
         ',name))))

(cl:defun %pcase--dontcare-p (pat)
  (and (symbolp pat) (or (eq pat '_) (eq pat t) (eq pat 'pcase--dontcare))))

(cl:defun pcase--trivial-upat-p (upat)
  "Bring-up shim for upstream `pcase--trivial-upat-p'."
  (and (symbolp upat)
       (not (memq upat
                  (let ((v (and (boundp 'pcase--dontcare-upats) (symbol-value 'pcase--dontcare-upats))))
                    (if (listp v) v '(t _ pcase--dontcare)))))))

(cl:defun %pcase--comma-form-p (x)
  (and (consp x) (symbolp (car x)) (string= (symbol-name (car x)) ",")))

(cl:defun %pcase--comma-at-form-p (x)
  (and (consp x) (symbolp (car x)) (string= (symbol-name (car x)) ",@")))

(cl:defun %pcase--bq-form-p (x)
  (and (consp x) (symbolp (car x)) (string= (symbol-name (car x)) "`")))

(cl:defun %pcase--collect-vars (pat)
  (let ((vars nil))
    (labels ((walk (p)
               (cond
                ((%pcase--dontcare-p p) nil)
                ((symbolp p) (pushnew p vars :test #'eq))
                ((%pcase--comma-form-p p)
                 (when (= (length p) 2) (walk (cadr p))))
                ((%pcase--comma-at-form-p p)
                 (when (= (length p) 2) (walk (cadr p))))
                ((%pcase--bq-form-p p)
                 (when (= (length p) 2) (walk (cadr p))))
                ((consp p)
                 (walk (car p))
                 (walk (cdr p)))
                (t nil))))
      (walk pat))
    (nreverse vars)))

(cl:defun %pcase--template->lambda-list (tmpl)
  "Translate a backquote template TMPL into a destructuring-bind lambda list.

Returns (values LAMBDA-LIST CHECKS SUBPATTERNS BINDINGS), where:
- LAMBDA-LIST is suitable for CL:DESTRUCTURING-BIND.
- CHECKS is a list of forms (in terms of the destructured vars) that must hold.
- SUBPATTERNS is a list of (VAR PATTERN) pairs for elements introduced as
  temporaries that need additional pcase matching.
- BINDINGS is the list of ELisp variables introduced."
  (let ((checks nil)
        (subpatterns nil)
        (bindings nil))
    (labels ((gen-elt (x)
               (cond
                ((%pcase--comma-form-p x)
                 (let ((p (cadr x)))
                   (cond
                    ((%pcase--dontcare-p p) (gensym "_"))
                    ((symbolp p) (pushnew p bindings :test #'eq) p)
                    (t
                     (let ((g (gensym "PCASE-")))
                       (push (list g p) subpatterns)
                       g)))))
                ((%pcase--comma-at-form-p x)
                 (let ((p (cadr x)))
                   (cond
                    ((%pcase--dontcare-p p) (list '&rest (gensym "_")))
                    ((symbolp p) (pushnew p bindings :test #'eq) (list '&rest p))
                    (t
                     (let ((g (gensym "REST-")))
                       (push (list g p) subpatterns)
                       (list '&rest g))))))
                ((consp x)
                 ;; Dotted cdr patterns in backquote templates (e.g.
                 ;; `(and ,first . ,rest)) are read by Lisp as a proper list
                 ;; whose tail is the unquote operator and its operand:
                 ;;   (AND (\, FIRST) \\, REST)
                 ;; Recognize that suffix and translate it into a dotted
                 ;; destructuring lambda list: (AND FIRST . REST).
                 (let* ((proper-len (list-length x)))
                   (when (and proper-len (>= proper-len 2))
                     (let* ((tail2 (last x 2))
                            (marker (first tail2))
                            (pat (second tail2)))
                       (when (and (symbolp marker)
                                  (or (string= (symbol-name marker) ",")
                                      (string= (symbol-name marker) ",@")))
                         (let* ((prefix (butlast x 2))
                                (prefix-ll (mapcar #'gen-elt prefix))
                                (tail-ll
                                  (cond
                                   ((%pcase--dontcare-p pat) (gensym "_"))
                                   ((symbolp pat) (pushnew pat bindings :test #'eq) pat)
                                   (t
                                    (let ((g (gensym "PCASE-TAIL-")))
                                      (push (list g pat) subpatterns)
                                      g))))
                                (ll (if (null prefix-ll)
                                        tail-ll
                                        (reduce (lambda (acc elt) (cons elt acc))
                                                (reverse prefix-ll)
                                                :initial-value tail-ll))))
                           (return-from gen-elt ll))))))
                 (let ((car (gen-elt (car x)))
                       (cdr (gen-elt (cdr x))))
                   (cond
                    ((and (consp car) (eq (car car) '&rest))
                     (cl:error "pcase: ,@ only supported in list tail position"))
                    ((and (consp cdr) (eq (car cdr) '&rest))
                     (cons car cdr))
                    (t (cons car cdr)))))
                ((null x) nil)
                ((vectorp x)
                 ;; Basic vector destructuring: translate to a list of elements.
                 (let ((lst (map 'list #'identity x)))
                   (coerce (mapcar #'gen-elt lst) 'vector)))
                (t
                 (let ((g (gensym "K-")))
                   (push `(elisp:equal ,g ',x) checks)
                   g)))))
      (let ((ll (gen-elt tmpl)))
        (cl:values ll (nreverse checks) (nreverse subpatterns) (nreverse bindings))))))

(cl:defun %pcase--fun-placeholder-p (x)
  (and (symbolp x) (string= (symbol-name x) "_")))

(cl:defun %pcase--elisp-keyword-p (sym)
  "Return non-nil if SYM should be treated as an ELisp keyword constant.

In ELisp, keywords are self-evaluating symbols whose names start with \":\".
Upstream `pcase' patterns treat those as constants (not variable bindings)."
  (and (symbolp sym)
       (let ((name (symbol-name sym)))
         (and (cl:plusp (length name))
              (cond
               ((cl:stringp name)
                (char= (char name 0) #\:))
               ((or (vectorp name) (unibyte-string-p name))
                (= (aref name 0) (char-code #\:)))
               (t nil))))))

(cl:defun %pcase--emit-fun-call (fun val)
  "Return code that calls FUN with VAL inserted per `pcase' rules."
  (cond
   ((symbolp fun) `(,fun ,val))
   ((and (consp fun) (eq (car fun) 'lambda))
    `(funcall (function ,fun) ,val))
   ((and (consp fun) (symbolp (car fun)))
    (let* ((f (car fun))
           (args (cdr fun))
           (pos (position-if #'%pcase--fun-placeholder-p args)))
      (if pos
          `(,f ,@(subseq args 0 pos) ,val ,@(subseq args (1+ pos)))
        `(,f ,@args ,val))))
   (t
    (cl:error "pcase: unsupported FUN in pred/app: ~S" fun))))

(cl:defun %pcase--emit-match--emit (pat val ft fv k)
  (when (and (consp pat) (symbolp (car pat)))
    (let ((exp (%pcase--get-pattern-macroexpander (car pat))))
      (when exp
        (return-from %pcase--emit-match--emit
          (%pcase--emit-match--emit (apply exp (cdr pat)) val ft fv k)))))
  (cond
   ((%pcase--dontcare-p pat) k)
   ((%pcase--bq-form-p pat)
    (let ((tmp (gensym "PCASE-TMP-")))
      (multiple-value-bind (ll checks subpatterns _vars)
          (%pcase--template->lambda-list (cadr pat))
        (declare (cl:ignore _vars))
        (dolist (sp (reverse subpatterns))
          (destructuring-bind (var subpat) sp
            (setf k (%pcase--emit-match--emit subpat var ft fv k))))
        ;; `destructuring-bind' requires a list-ish lambda list.  For atomic
        ;; backquote templates like `t or `,x, %PCASE--TEMPLATE->LAMBDA-LIST
        ;; returns a single symbol binding; treat that as "bind whole value".
        (if (symbolp ll)
            `(let* ((,tmp ,val)
                    (,ll ,tmp))
               (unless (and ,@checks)
                 (return-from ,ft ,fv))
               ,k)
            `(let ((,tmp ,val))
               (handler-case
                   (destructuring-bind ,ll ,tmp
                     (unless (and ,@checks)
                       (return-from ,ft ,fv))
                     ,k)
                 (cl:error ()
                   (return-from ,ft ,fv))))))))
   ((and (consp pat) (eq (car pat) 'or))
    (let ((or-done (gensym "PCASE-OR-")))
      `(block ,or-done
         ,@(mapcar
            (lambda (p)
              (let ((alt-fail (gensym "PCASE-ALT-FAIL-")))
                `(block ,alt-fail
                   ,(%pcase--emit-match--emit p val alt-fail nil
                                             `(return-from ,or-done (progn ,k)))
                   nil)))
            (cdr pat))
         (return-from ,ft ,fv))))
   ((and (consp pat) (eq (car pat) 'and))
    (let ((acc k))
      (dolist (p (reverse (cdr pat)) acc)
        (setf acc (%pcase--emit-match--emit p val ft fv acc)))))
   ((and (consp pat) (eq (car pat) 'guard) (= (length pat) 2))
    `(if ,(cadr pat) ,k (return-from ,ft ,fv)))
   ((and (consp pat) (eq (car pat) 'pred) (= (length pat) 2))
    (let ((pred (cadr pat)))
      (cond
       ((symbolp pred)
        `(if (,pred ,val) ,k (return-from ,ft ,fv)))
       ((and (consp pred) (eq (car pred) 'not)
             (consp (cdr pred)) (null (cddr pred)))
        (let ((inner (cadr pred)))
          `(if (not ,(%pcase--emit-fun-call inner val))
               ,k
               (return-from ,ft ,fv))))
       (t
        `(if ,(%pcase--emit-fun-call pred val) ,k (return-from ,ft ,fv))))))
   ((and (consp pat) (eq (car pat) 'app) (= (length pat) 3))
    (let ((tmp (gensym "PCASE-APP-")))
      `(let ((,tmp ,(%pcase--emit-fun-call (cadr pat) val)))
         ,(%pcase--emit-match--emit (caddr pat) tmp ft fv k))))
   ((and (consp pat) (eq (car pat) 'let) (= (length pat) 3))
    (let ((tmp (gensym "PCASE-LET-")))
      `(let ((,tmp ,(caddr pat)))
         ,(%pcase--emit-match--emit (cadr pat) tmp ft fv k))))
   ((and (consp pat) (eq (car pat) 'quote) (= (length pat) 2))
    `(if (elisp:equal ,val ',(cadr pat)) ,k (return-from ,ft ,fv)))
   ((or (integerp pat) (cl:stringp pat))
    `(if (elisp:equal ,val ,pat) ,k (return-from ,ft ,fv)))
   ((and (symbolp pat)
         (or (eq (symbol-package pat) (find-package "KEYWORD"))
             (%pcase--elisp-keyword-p pat)))
    `(if (eq ,val ',pat) ,k (return-from ,ft ,fv)))
   ((null pat)
    `(if (null ,val) ,k (return-from ,ft ,fv)))
   ((and (symbolp pat) (not (eq pat t)))
    ;; ELisp pcase binds symbols as variables.  We treat all
    ;; non-keyword symbols (except don'tcare patterns above) as
    ;; bindings.
    `(let ((,pat ,val)) ,k))
   (t
    (cl:error "pcase: unsupported pattern: ~S" pat))))

(cl:defun %pcase--emit-match (pattern value-sym fail-tag fail-value cont)
  "Return code that matches PATTERN against VALUE-SYM and runs CONT on success.

On mismatch, `return-from' FAIL-TAG with FAIL-VALUE."
  (%pcase--emit-match--emit pattern value-sym fail-tag fail-value cont))

(cl:defmacro pcase-let* (bindings &rest body)
  "Bring-up subset of ELisp `pcase-let*'.

Supports destructuring patterns of the form:
- SYMBOL (binds the whole value)
- `_`/`t` (don't care)
- backquote templates using `\, and `\,@ (from the ELisp reader).
- pattern macros defined via `pcase-defmacro' (e.g. `seq' from `seq.el')."
  (let ((forms body))
    (labels
        ((expand (bs)
           (if (null bs)
               `(progn ,@forms)
               (destructuring-bind (pat expr) (car bs)
                 (cond
                  ((%pcase--dontcare-p pat)
                   `(let ((,(gensym "_") ,expr))
                      ,(expand (cdr bs))))
                  ((symbolp pat)
                   `(let ((,pat ,expr))
                      ,(expand (cdr bs))))
                  (t
                   (let* ((tmp (gensym "PCASE-VALUE-"))
                          (fail-tag (gensym "PCASE-LET*-FAIL-"))
                          (fail-marker (gensym "PCASE-LET*-MISMATCH-"))
                          (k (expand (cdr bs)))
                          (match-form
                            (%pcase--emit-match pat tmp fail-tag `',fail-marker k)))
                     `(let ((,tmp ,expr))
                        (let ((res (block ,fail-tag ,match-form)))
                          (when (eq res ',fail-marker)
                            (error "pcase-let*: pattern mismatch: %S %S" ',pat ,tmp))
                          res)))))))))
      (expand bindings))))

(cl:defmacro pcase-let (bindings &rest body)
  "Bring-up subset of ELisp `pcase-let'."
  `(pcase-let* ,bindings ,@body))

(cl:defmacro pcase-dolist (spec &rest body)
  "Bring-up subset of ELisp `pcase-dolist'."
  (destructuring-bind (pat listform) spec
    (if (%pcase--dontcare-p pat)
        `(dolist (_ ,listform) ,@body)
      (let ((tmp (gensym "PCASE-ELT-")))
        `(dolist (,tmp ,listform)
           (pcase-let* ((,pat ,tmp))
             ,@body))))))

(cl:defmacro defgroup (name _parents _docstring &rest _args)
  "Stub for ELisp `defgroup'."
  (declare (cl:ignore _parents _docstring _args))
  `(progn ',name))

(cl:defmacro defcustom (symbol value _docstring &rest _args)
  "Stub for ELisp `defcustom'."
  (declare (cl:ignore _docstring _args))
  `(defparameter ,symbol ,value))

(cl:defmacro defface (face _spec _docstring &rest _args)
  "Stub for ELisp `defface'."
  (declare (cl:ignore _spec _docstring _args))
  `(progn ',face))

(cl:defmacro define-globalized-minor-mode (global-mode mode turn-on &rest args)
  "Bring-up stub for ELisp `define-globalized-minor-mode'.

This defines GLOBAL-MODE as a global minor mode toggler.  During bring-up we
don't yet walk buffers or manage mode hooks, but we do define the variable and
command so preloaded startup files can be checkpointed."
  (declare (cl:ignore mode turn-on))
  (let ((init-value nil))
    (loop for (k v) on args by #'cddr do
      (when (eq k :init-value)
        (setf init-value v)))
    `(progn
       (defvar ,global-mode ,init-value)
       (defun ,global-mode (&optional arg)
         (declare (cl:ignore arg))
         (setf ,global-mode (not (not ,global-mode)))
         ,global-mode)
       ',global-mode)))

(cl:defun define-error (name message &optional parent)
  "Bring-up subset of ELisp `define-error'.

Records enough symbol properties for upstream ERT's `should-error':
- `error-message'
- `error-conditions' (a list of symbols, rooted at `error')."
  (unless (symbolp name)
    (cl:error "ELISP:DEFINE-ERROR expected symbol NAME, got: ~S" name))
  (unless (stringp message)
    (cl:error "ELISP:DEFINE-ERROR expected string MESSAGE, got: ~S" message))
  (unless (or (null parent) (symbolp parent))
    (cl:error "ELISP:DEFINE-ERROR expected symbol PARENT or nil, got: ~S" parent))
  (let* ((parent (or parent 'error))
         (parent-conds (get parent 'error-conditions)))
    (unless (and (listp parent-conds) (cl:member parent parent-conds :test #'eq))
      ;; Seed `error' if it wasn't populated yet.
      (setf parent-conds (list parent))
      (setf (get parent 'error-conditions) parent-conds))
    (setf (get name 'error-message) message)
    (setf (get name 'error-conditions)
          (cons name parent-conds))
    name))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Emacs seeds these in C (data.c / Fsignal setup).  Upstream ELisp
  ;; `define-error' (in lisp/subr.el) assumes they already exist, and ERT's
  ;; `ert--should-error-handle-error' asserts it can read them.
  (flet ((seed (sym conds message)
           (unless (get sym 'error-conditions)
             (setf (get sym 'error-conditions) conds))
           (unless (get sym 'error-message)
             (setf (get sym 'error-message) message))))
    (seed 'error
          (list 'error)
          "Error")
    ;; Minimal arithmetic hierarchy used by upstream ERT tests.
    (seed 'arith-error
          (list 'arith-error 'error)
          "Arithmetic error")
    (seed 'domain-error
          (list 'domain-error 'arith-error 'error)
          "Arithmetic domain error")
    (seed 'singularity-error
          (list 'singularity-error 'domain-error 'arith-error 'error)
          "Arithmetic singularity error")
    (seed 'beginning-of-buffer
          (list 'beginning-of-buffer 'error)
          "Beginning of buffer")
    (seed 'end-of-buffer
          (list 'end-of-buffer 'error)
          "End of buffer")
    (seed 'buffer-read-only
          (list 'buffer-read-only 'error)
          "Buffer is read-only")
    (seed 'quit
          (list 'quit 'error)
          "Quit")
    ;; Common argument/type errors used by upstream tests and core libs.
    (seed 'wrong-type-argument
          (list 'wrong-type-argument 'error)
          "Wrong type argument")
    (seed 'args-out-of-range
          (list 'args-out-of-range 'error)
          "Args out of range")
    ;; cl-generic condition names used by upstream tests (e.g. map.el).
    (seed 'cl-no-applicable-method
          (list 'cl-no-applicable-method 'error)
          "No applicable method")
    (seed 'cl-no-next-method
          (list 'cl-no-next-method 'error)
          "No next method")
    (seed 'wrong-number-of-arguments
          (list 'wrong-number-of-arguments 'error)
          "Wrong number of arguments")))

(cl:defmacro cl-assert (form &rest _args)
  "Bring-up subset of cl-lib's `cl-assert'.

Upstream ELisp often passes extra arguments (e.g. SHOW-ARGS, message
formatting). We currently ignore them and delegate to CL:ASSERT on FORM."
  (declare (cl:ignore _args))
  `(cl:assert ,form))

(cl:defmacro cl-defmacro (name lambda-list &body body)
  "Minimal subset of cl-lib's `cl-defmacro'."
  `(defmacro ,name ,lambda-list ,@body))

(cl:defmacro cl-defun (name lambda-list &body body)
  "Minimal subset of cl-lib's `cl-defun'."
  `(defun ,name ,lambda-list ,@body))
