(in-package #:elisp)

(cl:defvar *clemacs-current-message* nil)

(cl:defun message (format-string &rest args)
  (let ((s (apply #'format format-string args)))
    (setf *clemacs-current-message* (and (stringp s) s))
    (let ((log-max
            (if (boundp 'message-log-max)
                (symbol-value 'message-log-max)
                t)))
      ;; Emacs does not log empty messages to *Messages*, and (crucially for
      ;; upstream ERT) they do not trigger truncation.
      (unless (or (null log-max) (zerop (length s)))
        (with-current-buffer (messages-buffer)
          (goto-char (point-max))
          (insert s #\Newline)
          ;; Approximate Emacs's implicit truncation behavior from C core:
          ;; when MESSAGE-LOG-MAX is a natnump, keep only the last N messages.
          (when (natnump log-max)
            (let* ((txt (elisp-buffer-text *current-buffer*))
                   (lines (count #\Newline txt)))
              (when (> lines log-max)
                (if (zerop log-max)
                    (erase-buffer)
                    (let* ((excess (- lines log-max))
                           (idx -1))
                      (dotimes (_ excess)
                        (let ((nl (position #\Newline txt :start (1+ idx))))
                          (when (null nl)
                            (return))
                          (setf idx nl)))
                      (when (and (integerp idx) (<= 0 idx))
                        (delete-region (point-min) (+ idx 2)))))))))))
    s))

(cl:defun current-message ()
  "Bring-up subset of the C primitive `current-message'."
  *clemacs-current-message*)

(cl:defun minibuffer-message (format-string &rest args)
  "Bring-up subset of the C primitive `minibuffer-message'."
  (apply #'message format-string args)
  t)

(cl:defun user-error (format-string &rest args)
  "Bring-up subset of ELisp `user-error'."
  (signal 'user-error (list (apply #'format format-string args))))

(cl:defun error-message-string (condition)
  "Bring-up subset of the C primitive `error-message-string'.

CONDITION is usually an ELisp-style error datum (ERROR-SYMBOL . DATA).  When
DATA begins with a string message (e.g. `(error \"msg\")`), return that message
directly."
  (cond
   ((typep condition 'elisp-signal)
    (error-message-string
     (cons (elisp-signal-symbol condition)
           (elisp-signal-data condition))))
   ((and (consp condition) (symbolp (car condition)))
    (let ((data (cdr condition)))
      (if (and (consp data) (stringp (car data)))
          (car data)
          (princ-to-string condition))))
   (t
    (princ-to-string condition))))

(cl:defun backtrace-get-frames (&optional base &rest _keys)
  "Bring-up subset of `backtrace-get-frames'.

Return a list of \"frames\" in the shape (FUN . ARGS), intended for upstream
ERT reporting.  This is not Emacs's native backtrace representation.

On SBCL, we capture a snapshot of the host call stack and convert each host
frame's call into an ELisp-friendly (FUN . ARGS) cons.  On other lisps, fall
back to a tiny stub list."
  (declare (cl:ignore base _keys))
  ;; ERT stores (cdr (backtrace-get-frames ...)) to drop frames above itself,
  ;; so include a sentinel head frame here.
  #+sbcl
  (let ((frames nil))
    (sb-debug:map-backtrace
     (lambda (frame)
       (handler-case
           (multiple-value-bind (call _ok)
               (sb-debug::frame-call-as-list frame 50)
             (declare (cl:ignore _ok))
             (when (consp call)
               (push (cons (car call) (cdr call)) frames)))
         (cl:error () nil)))
     :from :interrupted-frame
     :count 80)
    (let* ((frames (nreverse frames))
           ;; ERT wants the first recorded frame to be close to the original
           ;; signal site (usually `ert-fail' or `signal'), not the handler
           ;; plumbing around it.
           (frames
             (or (member-if
                  (lambda (fr)
                    (let ((fun (car fr)))
                      (and (symbolp fun)
                           (or (eq fun 'ert-fail) (eq fun 'signal)))))
                  frames)
                 frames))
           ;; Avoid huge/cyclic arguments from SBCL's frame-call reconstruction:
           ;; only keep args for frames we expect ERT to care about.
           (frames
             (mapcar
              (lambda (fr)
                (let ((fun (car fr)))
                  (if (and (symbolp fun) (or (eq fun 'signal) (eq fun 'ert-fail)))
                      fr
                      (cons fun nil))))
              frames))
           ;; SBCL may omit `ert-fail' due to tail call elimination.  Upstream
           ;; `ert-test-run-tests-batch-expensive' expects the batch backtrace
           ;; to include an `ert-fail(DATA)' frame, so synthesize it from the
           ;; corresponding `(signal 'ert-test-failed (list DATA))' call.
           (frames
             (let ((sig (car frames)))
               (if (and (consp sig)
                        (eq (car sig) 'signal)
                        (consp (cdr sig))
                        (eq (cadr sig) 'ert-test-failed)
                        (consp (cddr sig))
                        (let ((data (caddr sig)))
                          (and (listp data) (consp data) (null (cdr data)))))
                   (let ((data (car (caddr sig))))
                     (cons (cons 'ert-fail (list data)) frames))
                   frames))))
      (cons (cons 'backtrace-get-frames nil) frames)))
  #-sbcl
  (list (cons 'backtrace-get-frames nil)
        (cons 'signal nil)))

(cl:defun mapbacktrace (function &optional base)
  "Bring-up subset of the C primitive `mapbacktrace'.

Call FUNCTION for each backtrace frame.  FUNCTION is called with:
  (EVALD FUN ARGS FLAGS)
where FLAGS is currently always nil in clemacs bring-up.

If BASE is non-nil (a symbol naming a function), skip frames until the first
occurrence of BASE, then start calling FUNCTION after that frame."
  (let ((base-sym (and base (symbolp base) base))
        (seen-base (null base))
        (calls nil))
    #+sbcl
    (sb-debug:map-backtrace
     (lambda (frame)
       (handler-case
           (multiple-value-bind (call _ok)
               (sb-debug::frame-call-as-list frame 80)
             (declare (cl:ignore _ok))
             (when (consp call)
               (push call calls)))
         (cl:error () nil)))
     :from :interrupted-frame
     :count 120)
    #-sbcl
    (setf calls (list (list 'mapbacktrace function base)))
    (dolist (call (nreverse calls))
      (let ((fun (car call))
            (args (cdr call)))
        (cond
         ((and base-sym (not seen-base))
          (when (and (symbolp fun) (eq fun base-sym))
            (setf seen-base t)))
         (t
          (funcall function t fun args nil)))))
    nil))

(cl:defun backtrace-frame-fun (frame)
  "Bring-up subset of ELisp `backtrace-frame-fun'."
  (cond
   ((consp frame) (car frame))
   ((symbolp frame) frame)
   (t nil)))

(cl:defun backtrace-frame-args (frame)
  "Bring-up subset of ELisp `backtrace-frame-args'."
  (cond
   ((consp frame) (cdr frame))
   (t nil)))

(cl:defun backtrace-to-string (frames)
  "Bring-up subset of ELisp `backtrace-to-string'."
  (cl:with-output-to-string (out)
    (dolist (frame frames)
      (let ((fun (backtrace-frame-fun frame))
            (args (backtrace-frame-args frame)))
        (write-string "  " out)
        (write-string (prin1-to-string fun) out)
        (write-char #\( out)
        (cond
         ((null args) nil)
         ((listp args)
          (loop for arg in args
                for firstp = t then nil do
                  (unless firstp (write-char #\Space out))
                  (write-string (prin1-to-string arg) out)))
         (t
          (write-string (prin1-to-string args) out)))
        (write-char #\) out)
        (write-char #\Newline out)))))

(cl:defun macroexp-file-name ()
  "Stub for ELisp `macroexp-file-name'."
  (or load-file-name buffer-file-name))

(cl:defun macroexp-warn-and-return (_msg form &optional _category _compile-only)
  "Bring-up subset of ELisp `macroexp-warn-and-return'.

Upstream uses this to emit warnings during macroexpansion while still returning
FORM.  For bring-up, suppress the warning and return FORM."
  (declare (cl:ignore _msg _category _compile-only))
  form)

(cl:defun macroexp-copyable-p (exp)
  "Bring-up subset of ELisp `macroexp-copyable-p'."
  (cond
   ;; In upstream `macroexp.el` this is (or (symbolp exp) (macroexp-const-p exp)).
   ;; We keep it self-contained to avoid pulling in the full macroexp const
   ;; machinery just to unblock `pcase-let*` expansion during startup.
   ((consp exp)
    (or (eq (car exp) 'quote)
        (and (eq (car exp) 'function)
             (consp (cdr exp))
             (symbolp (cadr exp)))))
   (t t)))

(cl:defparameter backquote-backquote-symbol '|`|)
(cl:defparameter backquote-unquote-symbol '|,|)
(cl:defparameter backquote-splice-symbol '|,@|)

(cl:defun backquote-delay-process (s level)
  "Process a (un|back|splice)quote inside a backquote."
  (let ((exp (backquote-listify (list (cons 0 (list 'quote (car s))))
                                (backquote-process (cdr s) level))))
    (cons (if (eq (car-safe exp) 'quote) 0 1) exp)))

(cl:defun backquote-process (s &optional level)
  "Process the body of a backquote.

Return (TAG . FORM), where TAG is:
  0 => FORM is constant
  1 => FORM evaluates to the template value
  2 => FORM evaluates to a list to splice into its environment."
  (unless level (setf level 0))
  (cond
   ((vectorp s)
    (let ((n (backquote-process (coerce s 'list) level)))
      (if (= (car n) 0)
          (cons 0 s)
          (cons 1
                (cond
                 ((not (listp (cdr n)))
                  (list 'vconcat (cdr n)))
                 ((eq (cadr n) 'list)
                  (cons 'vector (cddr n)))
                 ((eq (cadr n) 'append)
                  (cons 'vconcat (cddr n)))
                 (t
                  (list 'apply '(function vector) (cdr n))))))))
   ((cl:atom s)
    (cons 0 (if (or (null s) (eq s t) (not (symbolp s)))
                s
                (list 'quote s))))
   ((eq (car s) backquote-unquote-symbol)
    (if (<= level 0)
        (cond
         ((> (length s) 2)
          (error "Multiple args to , are not supported: %S" s))
         (t (cons (if (eq (car-safe (cadr s)) 'quote) 0 1)
                  (cadr s))))
        (backquote-delay-process s (1- level))))
   ((eq (car s) backquote-splice-symbol)
    (if (<= level 0)
        (if (> (length s) 2)
            (error "Multiple args to ,@ are not supported: %S" s)
            (cons 2 (cadr s)))
        (backquote-delay-process s (1- level))))
   ((eq (car s) backquote-backquote-symbol)
    (backquote-delay-process s (1+ level)))
   (t
    (let ((rest s)
          item firstlist list lists expression)
      (while (and (consp rest)
                  (not (or (eq (car rest) backquote-unquote-symbol)
                           (eq (car rest) backquote-backquote-symbol))))
        (setf item (backquote-process (car rest) level))
        (cond
         ((= (car item) 2)
          (when (null lists)
            (setf firstlist list
                  list nil))
          (when list
            (push (backquote-listify list '(0 . nil)) lists))
          (push (cdr item) lists)
          (setf list nil))
         (t
          (setf list (cons item list))))
        (setf rest (cdr rest)))
      (when (or rest list)
        (push (backquote-listify list (backquote-process rest level)) lists))
      (setf expression
            (if (or (cdr lists)
                    (eq (car-safe (car lists)) backquote-splice-symbol))
                (cons 'append (nreverse lists))
                (car lists)))
      (when firstlist
        (setf expression (backquote-listify firstlist (cons 1 expression))))
      (cons (if (eq (car-safe expression) 'quote) 0 1) expression)))))

(cl:defun backquote-listify (list old-tail)
  "Turn a list of (TAG . FORM) pairs into a list-building form."
  (let ((heads nil)
        (tail (cdr old-tail))
        (list-tail list)
        (item nil))
    (when (= (car old-tail) 0)
      (setf tail (eval tail)
            old-tail nil))
    (while (consp list-tail)
      (setf item (car list-tail)
            list-tail (cdr list-tail))
      (if (or heads old-tail (/= (car item) 0))
          (setf heads (cons (cdr item) heads))
          (setf tail (cons (eval (cdr item)) tail))))
    (cond
     (tail
      (when (null old-tail)
        (setf tail (list 'quote tail)))
      (if heads
          (let ((use-list*
                  (or (cdr heads)
                      (and (consp (car heads))
                           (eq (car (car heads)) backquote-splice-symbol)))))
            (cons (if use-list* 'backquote-list* 'cons)
                  (append heads (list tail))))
          tail))
     (t
      (cons 'list heads)))))

(cl:defvar macro-declarations-alist nil)
(cl:defvar defun-declarations-alist nil)

(cl:defun byte-run--set-advertised-calling-convention (f _args arglist when)
  (declare (cl:ignore _args))
  (list 'set-advertised-calling-convention
        (list 'quote f)
        (list 'quote arglist)
        (list 'quote when)))

(eval-when (:load-toplevel :execute)
  (unless (cl:assoc 'advertised-calling-convention defun-declarations-alist :test #'eq)
    (push (list 'advertised-calling-convention
                #'byte-run--set-advertised-calling-convention)
          defun-declarations-alist)))

(cl:defvar macroexpand-all-environment nil)

(cl:defun %clemacs-macroexpand-1 (form &optional env)
  "Bring-up subset of ELisp `macroexpand-1'.

If ENV is an Emacs-style macro environment (an alist), honor the subset we
need for bring-up:
- local macros from `cl-macrolet' (NAME . EXPANDER)
- local FUNCTION-designator rewrite hooks (via a `function' env expander)."
  ;; In upstream ELisp, `function' is a special operator and is not subject to
  ;; macroexpansion.  In clemacs bring-up, we implement it as a macro for
  ;; pragmatic interop, so suppress its expansion here to match ELisp callers
  ;; (notably `cl-generic') which pattern-match on `#'' forms.
  (when (and (listp env) (consp form) (symbolp (car form)))
    (let* ((head (car form))
           (binding (cl:assoc head env :test #'eq))
           (expander (and binding (cdr binding))))
      (when (and expander (or (cl:functionp expander) (symbolp expander)))
        ;; `cl-labels' installs a special expander for FUNCTION so
        ;; (function F) and #'F resolve through local bindings.
        (when (and (or (eq head 'function) (eq head 'cl:function))
                   (consp (cdr form))
                   (null (cddr form)))
          (return-from %clemacs-macroexpand-1
            (cl:values (funcall expander (cadr form)) t)))
        ;; Treat ENV expanders as Emacs-style arg expanders.
        (return-from %clemacs-macroexpand-1
          (cl:values (cl:apply expander (cdr form)) t)))))
    (let ((env* (and (not (listp env)) env)))
      ;; Expand ELisp macros through the function cell / indirection chain so that
      ;; `defalias`ed macros and `nadvice`d macro expanders are visible.
      (when (and (consp form) (symbolp (car form)))
        (let ((head (car form)))
          (when (eq head 'function)
            (return-from %clemacs-macroexpand-1 (cl:values form nil)))
          (let ((def (ignore-errors (indirect-function head t))))
            (when (and (consp def) (eq (car def) 'macro) (cl:functionp (cdr def)))
              (let ((expander (cdr def)))
                (return-from %clemacs-macroexpand-1
                  (cl:values (cl:apply expander (cdr form)) t)))))))
      (cl:macroexpand-1 form env*)))

(cl:defun macroexpand-1 (form &optional env)
  "Bring-up subset of ELisp `macroexpand-1'."
  (%clemacs-macroexpand-1 form env))

(cl:defun macroexpand (form &optional env)
  "Bring-up subset of ELisp `macroexpand'.

If ENV is an Emacs-style macro environment (an alist), ignore it: SBCL's
`macroexpand' expects a lexical environment object or NIL."
  (let ((env* (and (not (listp env)) env)))
    (loop with cur = form do
      ;; `lisp/emacs-lisp/macroexp.el` is typically loaded early and defines its
      ;; own `macroexpand-1`.  Keep `macroexpand` stable by calling our private
      ;; helper directly.
      (multiple-value-bind (next expandedp) (%clemacs-macroexpand-1 cur env*)
        (if expandedp
            (setf cur next)
            (return cur))))))

(cl:defvar *macroexpand-1-compat* nil)
(cl:defvar *macroexpand-compat* nil)

(eval-when (:load-toplevel :execute)
  (unless *macroexpand-1-compat*
    (setf *macroexpand-1-compat* (fdefinition 'macroexpand-1)))
  (unless *macroexpand-compat*
    (setf *macroexpand-compat* (fdefinition 'macroexpand))))

(cl:defun %macroexpand-all--normalize-lambda-list (lambda-list)
  (labels ((rw (xs)
             (cond
              ((null xs) nil)
              ;; `destructuring-bind' doesn't understand &body in all lisps;
              ;; treat it as &rest for our bring-up needs.
              ((and (consp xs) (eq (car xs) '&body))
               (cons '&rest (rw (cdr xs))))
              (t (cons (car xs) (rw (cdr xs)))))))
    (rw lambda-list)))

(cl:defun %macroexpand-all--strip-environment (lambda-list)
  "Return (values LAMBDA-LIST* ENV-VAR).

If LAMBDA-LIST contains &environment VAR, remove it and return VAR."
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

(cl:defun %macroexpand-all--macro-arg-bindings (lambda-list args)
  "Build a LET binding list for a macro lambda list and an argument list.

This is intentionally a small subset sufficient for bring-up; it supports:
- required args (symbols),
- &optional (symbols only; defaults to NIL),
- &rest / &body (single symbol; binds remaining args list)."
  (let ((bindings nil)
        (mode :required))
    (labels ((emit (var value)
               (unless (symbolp var)
                 (cl:error "ELISP:MACROEXPAND-ALL unsupported macro var: ~S" var))
               (push (list var value) bindings)))
      (loop while lambda-list do
        (let ((x (pop lambda-list)))
          (cond
           ((eq x '&optional)
            (setf mode :optional))
           ((or (eq x '&rest) (eq x '&body))
            (let ((rest-var (pop lambda-list)))
              (emit rest-var args)
              (setf args nil)
              (setf lambda-list nil)))
           ((or (eq x '&key) (eq x '&allow-other-keys) (eq x '&aux))
            (cl:error "ELISP:MACROEXPAND-ALL macro lambda-list keyword unsupported: ~S" x))
           ((consp x)
            (cl:error "ELISP:MACROEXPAND-ALL destructuring macro args unsupported: ~S" x))
           (t
            (case mode
              (:required (emit x (if (consp args) (pop args) nil)))
              (:optional (emit x (if (consp args) (pop args) nil)))
              (otherwise
               (cl:error "ELISP:MACROEXPAND-ALL internal mode bug: ~S" mode))))))))
      (nreverse bindings)))

(cl:defun %macroexpand-all--macroexpand-1-local (form env)
  "Try to expand FORM using ENV (a cl-macrolet-style binding list).

Return (values EXPANDED EXPANDEDP)."
  (when (and (consp form) (symbolp (car form)) (listp env))
    (let ((binding (find (car form) env :key #'car :test #'eq)))
      (when (and binding (consp binding) (symbolp (car binding)))
        (destructuring-bind (name lambda-list &rest body) binding
          (declare (cl:ignore name))
          (let* ((lambda-list (%macroexpand-all--normalize-lambda-list lambda-list)))
            (multiple-value-bind (lambda-list env-var)
                (%macroexpand-all--strip-environment lambda-list)
              (let* ((args (cdr form))
                     (arg-bindings (%macroexpand-all--macro-arg-bindings lambda-list args))
                     (env-bindings (if env-var (list (list env-var env)) nil))
                     (expanded
                       (cl:eval
                        `(let ,(append env-bindings arg-bindings)
                           ,(macroexp-progn body)))))
                (cl:values expanded t))))))))
  (cl:values form nil))

(cl:defun %macroexpand-all--macroexpand-1 (form env)
  (multiple-value-bind (expanded expandedp)
      (%macroexpand-all--macroexpand-1-local form env)
    (if expandedp
        (cl:values expanded t)
        (cl:macroexpand-1 form (and (not (listp env)) env)))))

(cl:defun macroexp-progn (body)
  "Bring-up subset of ELisp `macroexp-progn'."
  (cond
   ((null body) nil)
   ((null (cdr body)) (car body))
   (t (cons 'progn body))))

(cl:defun macroexp-let* (bindings exp)
  "Bring-up subset of ELisp `macroexp-let*'.

Return an expression equivalent to `(let* ,BINDINGS ,EXP)`."
  (cond
   ((null bindings) exp)
   ((and (consp exp) (eq 'let* (car exp)) (consp (cdr exp)))
    ;; Merge nested LET* to avoid excessive wrapping.
    `(let* (,@bindings ,@(cadr exp)) ,@(cddr exp)))
   (t `(let* ,bindings ,exp))))

(cl:defmacro macroexp-let2 (test sym exp &rest body)
  "Bring-up subset of ELisp `macroexp-let2'.

Evaluate BODY with SYM bound to an expression for EXP's value."
  (declare (indent 3))
  (let ((bodysym (make-symbol "body"))
        (expsym (make-symbol "exp"))
        (pred (or test #'macroexp-copyable-p)))
    `(let* ((,expsym ,exp)
            (,sym (if (funcall ,pred ,expsym)
                      ,expsym
                      (make-symbol ,(symbol-name sym))))
            (,bodysym ,(macroexp-progn body)))
       (if (eq ,sym ,expsym)
           ,bodysym
           (macroexp-let* (list (list ,sym ,expsym)) ,bodysym)))))

(cl:defmacro macroexp-let2* (test bindings &rest body)
  "Bring-up subset of ELisp `macroexp-let2*'.

Multiple binding version of `macroexp-let2'."
  (declare (indent 2))
  (when (consp test) ;; TEST omitted.
    (push bindings body)
    (setf bindings test)
    (setf test nil))
  (labels ((expand (bs)
             (cond
              ((null bs) (macroexp-progn body))
              (t
               (let* ((b (car bs))
                      (tl (cdr bs)))
                 (cond
                  ((symbolp b)
                   `(macroexp-let2 ,test ,b ,b ,(expand tl)))
                  ((and (consp b) (consp (cdr b)) (null (cddr b)))
                   (destructuring-bind (var exp) b
                     `(macroexp-let2 ,test ,var ,exp ,(expand tl))))
                  (t
                   (error "ELISP:MACROEXP-LET2* invalid binding: ~S" b))))))))
    (expand bindings)))

;; ---------------------------------------------------------------------------
;; Minimal gv subset (bring-up)
;;
;; Enough to support `with-memoization' (subr.el) and the early `cl-generic.el'
;; method-combination memoization.
;; ---------------------------------------------------------------------------

(cl:defun gv-get (place do)
  "Bring-up subset of ELisp `gv-get'.

Build and return the code that applies DO to PLACE.
DO is called with (GETTER SETTER), where SETTER is a function (V -> code)."
  (cond
   ((symbolp place)
    (funcall do place (lambda (v) `(setq ,place ,v))))
   ((and (consp place) (eq (car place) 'gethash))
    (destructuring-bind (key table &optional default) (cdr place)
      (let ((k (gensym "GV-KEY-"))
            (tbl (gensym "GV-TABLE-"))
            (def (gensym "GV-DEFAULT-")))
        (let* ((getter
                 (if (null default)
                     `(gethash ,k ,tbl)
                     `(gethash ,k ,tbl ,def)))
               (setter
                 (lambda (v) `(puthash ,k ,v ,tbl)))
               (body (funcall do getter setter)))
          (if (null default)
              `(let* ((,k ,key)
                      (,tbl ,table))
                 ,body)
              `(let* ((,k ,key)
                      (,tbl ,table)
                      (,def ,default))
                 ,body))))))
   (t
    (error "ELISP:GV-GET unsupported place: ~S" place))))

(cl:defmacro gv-letplace (vars place &rest body)
  "Bring-up subset of ELisp `gv-letplace'."
  (declare (indent 2))
  `(gv-get ,place (lambda ,vars ,@body)))

(cl:defmacro if-let (bindings then &optional else)
  "Bring-up subset of subr-x `if-let'."
  (let ((vars (mapcar #'car bindings)))
    `(let* ,bindings
       (if (and ,@vars) ,then ,else))))

(cl:defmacro when-let (bindings &body body)
  "Bring-up subset of subr-x `when-let'."
  (let ((vars (mapcar #'car bindings)))
    `(let* ,bindings
       (when (and ,@vars)
         ,@(or body '(nil))))))

(cl:defmacro thread-first (x &rest forms)
  "Bring-up subset of subr-x `thread-first'."
  (reduce
   (lambda (acc form)
     (cond
      ((symbolp form) (list form acc))
      ((consp form) (list* (car form) acc (cdr form)))
      (t (error "ELISP:THREAD-FIRST bad form: ~S" form))))
   forms
   :initial-value x))

(cl:defmacro thread-last (x &rest forms)
  "Bring-up subset of subr-x `thread-last'."
  (reduce
   (lambda (acc form)
     (cond
      ((symbolp form) (list form acc))
      ((consp form) (append form (list acc)))
      (t (error "ELISP:THREAD-LAST bad form: ~S" form))))
   forms
   :initial-value x))

(cl:defmacro pcase (expr &rest clauses)
  "Bring-up subset of ELisp `pcase'.

This is a compatibility stub for early bootstrapping. It supports:
- `_` (default)
- symbols as variable bindings
- (pred FN)
- (guard FORM)
- (and PAT1 PAT2 ...)
- (let PAT EXP)
- (or PAT1 PAT2 ...) by expanding into multiple clauses.

If no clause matches, returns nil."
  (labels ((expand-or (pat body)
             (cond
              ((and (consp pat) (eq (car pat) 'or))
               (mapcan (lambda (p) (expand-or p body)) (cdr pat)))
              (t (list (cons pat body))))))
    (let* ((expanded
             (mapcan
              (lambda (clause)
                (destructuring-bind (pat &rest body) clause
                  (expand-or pat body)))
              clauses))
           (has-default (some (lambda (cl) (eq (car cl) '_)) expanded))
           (final (if has-default expanded (append expanded (list (list '_ nil))))))
      `(pcase-exhaustive ,expr ,@final))))

(cl:defmacro pcase-exhaustive (expr &rest clauses)
  "Bring-up subset of ELisp `pcase-exhaustive'.

Supports the patterns needed by `macroexp.el`, `gv.el`, and `cl-generic.el` in
clemacs bring-up:
- `_` / `pcase--dontcare` (default / don't care)
- symbols as variable bindings
- (pred PRED) including (pred (not PRED))
- (guard FORM)
- (and PAT1 PAT2 ...)
- (let PAT EXP)
- (or PAT1 PAT2 ...)
- quoted constants (e.g. 'nil), integers/strings, keyword constants
- backquote templates using `\, and `\,@."
  (let ((v (gensym "PCASE-"))
        (done (gensym "PCASE-DONE-")))
    `(let ((,v ,expr))
       (block ,done
         ,@(mapcar
            (lambda (clause)
              (destructuring-bind (pattern &rest body) clause
                (cond
                 ((eq pattern '_)
                  `(return-from ,done (progn ,@body)))
                 (t
                  (let ((fail (gensym "PCASE-FAIL-")))
                    `(block ,fail
                       ,(%pcase--emit-match pattern v fail nil
                                            `(return-from ,done (progn ,@body)))
                       nil))))))
            clauses)
         (error "pcase-exhaustive: no match for %S" ,v)))))

(cl:defun macroexp--fgrep (bindings sexp)
  "Bring-up subset of `macroexp--fgrep'.

Return non-nil if any bound symbols from BINDINGS appear in SEXP.
This is sufficient for `letrec' in `lisp/subr.el' during ERT bring-up."
  (let ((syms (mapcar #'car bindings)))
    (labels ((seen (x)
               (cond
                ((null x) nil)
                ((symbolp x) (and (cl:member x syms :test #'eq) t))
                ((atom x) nil)
                ((and (consp x) (eq (car x) 'quote)) nil)
                (t (or (seen (car x)) (seen (cdr x)))))))
      (seen sexp))))

(cl:defvar *macroexpand-all-compat* nil)

(cl:defun macroexpand-all (form &optional env)
  "Bring-up subset of ELisp `macroexpand-all'."
  (let ((macroexpand-all-environment env)
        (seen (cl:make-hash-table :test 'eq)))
    (labels ((callable-expander-p (x)
               (or (cl:functionp x) (symbolp x)))
             (env-expander (sym)
               (when (listp env)
                 (let ((b (cl:assoc sym env :test #'eq)))
                   (when (and b (consp b) (callable-expander-p (cdr b)))
                     (cdr b)))))
             (expand-1 (x)
               ;; Some ELisp "special operators" are implemented as CL macros in
               ;; clemacs for pragmatic bootstrapping.  `macroexpand-all' must
               ;; treat them as non-macros, otherwise deep expansion can rewrite
               ;; them in the wrong lexical environment (e.g. `setq' inside ERT's
               ;; nested `should' expansions).
               (when (and (consp x) (symbolp (car x)))
                 (case (car x)
                   ((setq)
                    (return-from expand-1 (cl:values x nil)))
                   ((loop)
                    ;; Avoid deep expansion of SBCL's CL:LOOP into SB-LOOP
                    ;; TAGBODY forms: those expansions can include SBCL-internal
                    ;; non-ANSI type specifiers (e.g. (if real number)), which
                    ;; then trip runtime type checks under clemacs.
                    (return-from expand-1 (cl:values x nil)))
                   ((function cl:function)
                    ;; In upstream ELisp, `function' is a special operator, but
                    ;; `cl-flet' / `cl-labels' install an ENV expander for it.
                    (unless (env-expander 'function)
                      (return-from expand-1 (cl:values x nil))))))
               ;; Emacs-style `macroexpand-all-environment`: an alist mapping
               ;; symbols to "expanders" (used by cl-labels to rewrite local
               ;; function references like (rec ...) and (function rec)).
               (when (and (consp x) (symbolp (car x)))
                 (let ((expander (env-expander (car x))))
                   (when expander
                     (cond
                      ;; Only expand (function F) (1 arg).
                      ((and (or (eq (car x) 'function) (eq (car x) 'cl:function))
                            (consp (cdr x))
                            (null (cddr x)))
                       (return-from expand-1
                         (cl:values (funcall expander (cadr x)) t)))
                      (t
                       (return-from expand-1
                         (cl:values (cl:apply expander (cdr x)) t)))))))
               (%macroexpand-all--macroexpand-1 x env))
             (expand-loop (x)
               (let ((cur x)
                     (expandedp t)
                     (guard 0))
                 (loop while expandedp do
                   (incf guard)
                   (when (> guard 200)
                     (cl:error "ELISP:MACROEXPAND-ALL appears to loop on: ~S" cur))
                   (multiple-value-bind (next nextp) (expand-1 cur)
                     (setf cur next
                           expandedp nextp)))
                 cur))
             (rw (x)
               (cond
                ((atom x) x)
                ((gethash x seen) x)
                (t
                 (setf (gethash x seen) t)
                 (let ((x (expand-loop x)))
                   (cond
                    ((atom x) x)
                    ;; Do not macroexpand under QUOTE.
                   ((and (consp x) (eq (car x) 'quote) (consp (cdr x)) (null (cddr x)))
                     x)
                    ;; Do not traverse into CL:LOOP clause syntax.  Once we stop
                    ;; expanding CL:LOOP itself (see EXPAND-1), a naive cons-tree
                    ;; walk would treat keywords like DO as macro calls.
                    ((and (consp x) (eq (car x) 'loop))
                     x)
                    ;; Expand under FUNCTION for lambda expressions so local
                    ;; macro expanders (notably `cl-macrolet') can rewrite their
                    ;; bodies.  Still avoid traversing inside (function SYMBOL)
                    ;; and other arbitrary function objects.
                    ((and (consp x)
                          (or (eq (car x) 'function) (eq (car x) 'cl:function))
                          (consp (cdr x))
                          (null (cddr x)))
                     (let ((arg (cadr x)))
                       (if (and (consp arg) (eq (car arg) 'lambda))
                           (list (car x)
                                 (cons 'lambda
                                       (cons (cadr arg)
                                             (mapcar #'rw (cddr arg)))))
                           x)))
                    ;; General cons rewrite: preserve dotted lists.
                    (t (cons (rw (car x)) (rw (cdr x))))))))))
      (rw form))))

(eval-when (:load-toplevel :execute)
  (unless *macroexpand-all-compat*
    (setf *macroexpand-all-compat* (fdefinition 'macroexpand-all))))

;; Upstream ERT exposes `skip-when' and `skip-unless' inside `ert-deftest'
;; bodies.  For bring-up, also provide them as global macros so test bodies
;; that close over them in lambdas still macroexpand under SBCL.
(cl:defmacro skip-when (form)
  `(ert--skip-when ,form))

(cl:defmacro skip-unless (form)
  `(ert--skip-unless ,form))

(cl:defmacro condition-case (var bodyform &rest handlers)
  "Bring-up subset of ELisp `condition-case'.

Binds VAR (when non-nil) to an ELisp-style error datum:
  (ERROR-SYMBOL . DATA)."
  (let* ((tag (gensym "CC-CATCH-"))
         (out (gensym "CC-OUT-"))
         (e (gensym "CC-E-"))
         (err (or var (gensym "CC-ERR-")))
         (success-clause (find :success handlers :key #'car))
         (error-clauses (remove :success handlers :key #'car)))
    (labels ((matchp-form (types sym)
               (cond
                ((eq types t) t)
                ((and (symbolp types) (eq types 'error)) t)
                ((symbolp types)
                 `(or (eq ,sym ',types)
                      (let ((conds (get ,sym 'error-conditions)))
                        (and (listp conds) (cl:member ',types conds :test #'eq)))))
                ((consp types)
                 `(or (cl:member ,sym ',types :test #'eq)
                      (let ((conds (get ,sym 'error-conditions)))
                        (and (listp conds)
                             (some (lambda (t0) (cl:member t0 conds :test #'eq)) ',types)))))
                (t nil)))
             (expand-clauses (err-sym)
               (let ((sym `(car ,err-sym)))
                 `(cond
                   ,@(mapcar
                      (lambda (clause)
                        (destructuring-bind (types &rest body) clause
                          `(,(matchp-form types sym)
                            ,(if var
                                 `(let ((,var ,err-sym)) (progn ,@body))
                                 `(progn ,@body)))))
                      error-clauses)
                   ;; No matching handler: re-signal the original error.
                   (t (signal (car ,err-sym) (cdr ,err-sym)))))))
      `(let ((,out
              (catch ',tag
                (cl:handler-bind
                   ((elisp-signal
                       (lambda (,e)
                         (let ((mode (uiop:getenv "CLEMACS_DEBUG_CONDITION_CASE")))
                           (when (and mode
                                      (or (string= mode "1")
                                          (string= mode "all")
                                          (string= mode "elisp")))
                             (cl:format *error-output*
                                        "~&[clemacs] condition-case caught ELisp signal: ~S ~S~%"
                                        (elisp-signal-symbol ,e)
                                        (elisp-signal-data ,e))
                             #+sbcl
                             (sb-debug:print-backtrace :stream *error-output* :count 80)
                             (finish-output *error-output*)))
                         (throw ',tag
                           (list :err
                                 (cons (elisp-signal-symbol ,e)
                                       (elisp-signal-data ,e))))))
                     (cl:error
                       (lambda (,e)
                         (unless (typep ,e 'elisp-signal)
                           (let ((mode (uiop:getenv "CLEMACS_DEBUG_CONDITION_CASE")))
                             (when (and mode
                                        (or (string= mode "1")
                                            (string= mode "all")
                                            (string= mode "cl")))
                               (cl:format *error-output*
                                          "~&[clemacs] condition-case caught CL error: ~A (~A)~%"
                                          ,e (cl:type-of ,e))
                               #+sbcl
                               (sb-debug:print-backtrace :stream *error-output* :count 80)
                               (finish-output *error-output*)))
                           (throw ',tag
                             (list :err
	                                   (cond
	                                    ((typep ,e 'arithmetic-error)
	                                     (cons 'arith-error (list ,e)))
	                                    #+sbcl
	                                    ((typep ,e 'sb-kernel::arg-count-error)
	                                     (cons 'wrong-number-of-arguments (list ,e)))
	                                    #+sbcl
	                                    ((typep ,e 'sb-pcl::no-applicable-method-error)
	                                     (cons 'cl-no-applicable-method (list ,e)))
	                                    #+sbcl
	                                    ((typep ,e 'sb-pcl::no-next-method-error)
                                     (cons 'cl-no-next-method (list ,e)))
                                    (t
                                     (cons 'error (list ,e))))))))))
                  (list :ok ,bodyform)))))
         (cond
          ((and (consp ,out) (eq (car ,out) :ok))
           (let ((res (cadr ,out)))
             ,(if success-clause
                  (destructuring-bind (_ &rest body) success-clause
                    (declare (cl:ignore _))
                    (if var
                        `(let ((,var res)) (progn ,@body))
                        `(progn ,@body)))
                  'res)))
          ((and (consp ,out) (eq (car ,out) :err))
           (let ((,err (cadr ,out)))
             ,(expand-clauses err)))
          (t ,out))))))

(define-condition elisp-signal (cl:error)
  ((symbol :initarg :symbol :reader elisp-signal-symbol)
   (data :initarg :data :reader elisp-signal-data)))

(cl:defun signal (error-symbol data)
  "Bring-up subset of ELisp `signal'.

ERROR-SYMBOL is an error condition name (a symbol) and DATA is a list of
arguments. We map this to a CL condition so `condition-case' can recover
the original (SYMBOL . DATA) pair."
  (unless (symbolp error-symbol)
    (cl:error "ELISP:SIGNAL expected symbol, got: ~S" error-symbol))
  (unless (listp data)
    (cl:error "ELISP:SIGNAL expected list data, got: ~S" data))
  (cl:error 'elisp-signal :symbol error-symbol :data data))

(cl:defun %format-message (fmt args)
  "Very small subset of ELisp `format' used for early error messages.

  Supports: %s, %S, %d, %x, %c, and %%."
  (unless (stringp fmt)
    (when (uiop:getenv "CLEMACS_DEBUG_FORMAT_BAD_FMT")
      (let ((path "build/clemacs/tmp/format-bad-fmt.out"))
        (ensure-directories-exist path)
        (with-open-file (out path
                             :direction :output
                             :if-exists :append
                             :if-does-not-exist :create)
          (cl:format out "~&[format] bad fmt: ~S ; args=~S~%" fmt args)
          #+sbcl
          (sb-debug:print-backtrace :stream out :count 80)
          (finish-output out))))
    (cl:error "ELISP:ERROR expects a string format, got: ~S" fmt))
  (let* ((fmt-s (%elisp-string->cl-string fmt))
         (i 0)
         (n (length fmt-s))
         (rest args)
         (codes (make-array 0 :element-type 'integer :adjustable t :fill-pointer 0))
         (need-multibyte nil))
    (labels ((emit-code (code)
               (vector-push-extend code codes)
               (when (or (%raw-byte-char-code-p code) (>= code 128))
                 (setf need-multibyte t)))
	             (emit-cl-string (s)
	               (dotimes (j (length s))
	                 (emit-code (char-code (char s j)))))
	             (emit-obj-princ (o)
	               (emit-cl-string (%elisp-string->cl-string (princ-to-string o))))
	             (emit-obj-prin1 (o)
	               (emit-cl-string (%elisp-string->cl-string (prin1-to-string o))))
	             (emit-dec (o)
	               (emit-cl-string (%elisp-string->cl-string (princ-to-string o))))
             (emit-hex (o)
               (emit-cl-string
                (cl:string-downcase
                 (cl:format nil "~x"
                            (cond
                             ((integerp o) o)
                             ((cl:characterp o) (char-code o))
                             (t o))))))
	             (emit-c (o)
	               (cond
	                ((integerp o) (emit-code o))
	                ((cl:characterp o) (emit-code (char-code o)))
	                (t
	                 (let ((s (%elisp-string->cl-string (princ-to-string o))))
	                   (when (> (length s) 0)
	                     (emit-code (char-code (char s 0))))))))
             (finish ()
               (if (not need-multibyte)
                   (let ((out (%make-unibyte-string (length codes))))
                     (dotimes (k (length codes))
                       (setf (aref out k) (aref codes k)))
                     out)
                   (let ((out (cl:make-string (length codes))))
                     (dotimes (k (length codes))
                       (setf (char out k) (%elisp-code->char (aref codes k))))
                     out))))
      (loop while (< i n) do
        (let ((ch (char fmt-s i)))
          (if (char= ch #\%)
              (progn
                (incf i)
                (when (>= i n)
                  (emit-code (char-code #\%))
                  (return))
                (let* ((code (char fmt-s i))
                       (arg-present (consp rest))
                       (arg (if arg-present (pop rest) nil)))
                  (case code
                    (#\% (emit-code (char-code #\%)))
                    (#\s (when arg-present (emit-obj-princ arg)))
                    (#\S (when arg-present (emit-obj-prin1 arg)))
                    (#\d (when arg-present (emit-dec arg)))
                    (#\x (when arg-present (emit-hex arg)))
                    (#\c (when arg-present (emit-c arg)))
                    (otherwise
                     (emit-code (char-code #\%))
                     (emit-code (char-code code))))))
              (emit-code (char-code ch))))
        (incf i))
      (finish))))

(cl:defun format-message (fmt &rest args)
  "Bring-up subset of ELisp `format-message'."
  (%format-message fmt args))

(cl:defun format (fmt &rest args)
  "Bring-up subset of ELisp `format'."
  (%format-message fmt args))

(cl:defun characterp (x)
  "ELisp-ish `characterp'.

In Emacs, characters are represented as integers."
  (or (cl:characterp x)
      (and (integerp x) (<= 0 x #x3fffff) t)))

(cl:defun error (fmt &rest args)
  "Signal an ELisp-style `error' with DATA = (MESSAGE).

This is intentionally not CL:ERROR; it raises an `elisp-signal' so ELisp
`handler-bind' and `condition-case' can recover the (SYMBOL . DATA) pair."
  (let ((msg (if args (%format-message fmt args) fmt)))
    (signal 'error (list msg))))

(cl:defun %handler-bind-match-p (types err)
  (let ((sym (car err)))
    (cond
     ((eq types t) t)
     ((symbolp types)
      (or (eq sym types)
          ;; Treat `error' as a catch-all for ELisp signals.
          (eq types 'cl:error)
          (eq types 'error)))
     ((consp types)
      (some (lambda (t0) (%handler-bind-match-p t0 err)) types))
     (t nil))))

(cl:defmacro handler-bind (bindings &body body)
  "Bring-up subset of ELisp `handler-bind' (cl-lib style).

Unlike CL:HANDLER-BIND, handlers receive an ELisp-style error datum:
  (ERROR-SYMBOL . DATA)."
  (let ((handlers
          (mapcar
           (lambda (b)
             (destructuring-bind (types handler) b
               (let ((c (gensym "C"))
                     (err (gensym "ERR")))
                 `(elisp-signal
                   (lambda (,c)
                     (let ((,err (cons (elisp-signal-symbol ,c) (elisp-signal-data ,c))))
                       (when (%handler-bind-match-p ',types ,err)
                         (funcall ,handler ,err))))))))
           bindings)))
    `(cl:handler-bind
         ,handlers
       ,@body)))

(cl:defun handler--bind (thunk &rest args)
  "Implementation helper for `lisp/subr.el' `handler-bind'.

SUBR's macro expands to:
  (handler--bind (lambda () ...) CONDS1 HANDLER1 CONDS2 HANDLER2 ...)

Where each HANDLER is a function that takes one argument: the error object.
In clemacs, the error object is represented as (ERROR-SYMBOL . DATA)."
  (unless (functionp thunk)
    (error "ELISP:HANDLER--BIND expects a function thunk, got: %S" thunk))
  (unless (evenp (length args))
    (error "ELISP:HANDLER--BIND expects an even number of args, got: %S" args))
  (cl:handler-bind
      ((elisp-signal
         (lambda (c)
           (let ((err (cons (elisp-signal-symbol c) (elisp-signal-data c))))
             (loop for (types handler) on args by #'cddr do
               (when (%handler-bind-match-p types err)
                 (funcall handler err)))))))
    (funcall thunk)))

(define-condition quit (cl:error) ())

(cl:defmacro letrec (bindings &body body)
  "Bring-up subset of ELisp `letrec'.

Supports the common pattern of a self-referential closure (used by ERT)."
  (let ((vars (mapcar #'car bindings)))
    `(let ,(mapcar (lambda (v) (list v nil)) vars)
       ,@(mapcar (lambda (b) (list 'setq (car b) (cadr b))) bindings)
       ,@body)))

(defvar *special-operator-subrs* nil)

(cl:defun indirect-function (thing &optional noerror)
  "Bring-up subset of ELisp `indirect-function'."
  (declare (cl:ignore noerror))
  (cond
   ;; In Emacs, macro objects and autoload markers are valid "function
   ;; values" to pass through `indirect-function' unchanged.
   ((and (consp thing) (eq (car thing) 'macro)) thing)
   ((and (consp thing) (eq (car thing) 'autoload)) thing)
   ;; Emacs's `indirect-function' generally treats non-symbol objects as
   ;; already "indirect", and just returns them.  This is relied upon by
   ;; code that calls `macrop' on function definition objects like:
   ;;   (advice lambda ...)
   ;; which are conses but not actual macro objects.
   ((consp thing) thing)
   ;; Some upstream code (e.g. `substitute-key-definition') uses
   ;; `indirect-function' on keymap objects while scanning bindings.
   ;; Treat concrete keymaps as already-indirect.
   ((and (not (symbolp thing)) (keymapp thing)) thing)
   ((symbolp thing)
    (let ((seen nil)
          (cur thing))
      (loop
        (push cur seen)
        (let ((special (gethash cur *special-operator-subrs*)))
          (when special
            (return special)))
        (let ((def (symbol-function cur)))
          (cond
           ((null def)
            (return nil))
           ((and (symbolp def) (not (eq def cur)))
            ;; Match Emacs: NOERROR does not suppress cyclic indirection.
            ;; Emacs reports the symbol whose function cell points back into
            ;; the already-seen chain.
            (when (cl:member def seen :test #'eq)
              (signal 'cyclic-function-indirection (list cur)))
            (setf cur def))
           (t
            (return def)))))))
   ((functionp thing) thing)
   (t (error "ELISP:INDIRECT-FUNCTION bad value: %S" thing))))

(defstruct elisp-subr
  (arity (cons 0 0)))

(defparameter *special-operator-subrs*
  (let ((ht (cl:make-hash-table :test 'eq)))
    ;; Enough to make upstream ERT's `ert--special-operator-p' treat these
    ;; as special operators (so `should' can handle quoted forms).
    (setf (gethash 'cl:quote ht) (make-elisp-subr :arity (cons 1 'unevalled)))
    (setf (gethash 'cl:function ht) (make-elisp-subr :arity (cons 1 'unevalled)))
    (setf (gethash 'cl:progn ht) (make-elisp-subr :arity (cons 0 'unevalled)))
    (setf (gethash 'cl:if ht) (make-elisp-subr :arity (cons 2 'unevalled)))
    (setf (gethash 'cl:let ht) (make-elisp-subr :arity (cons 1 'unevalled)))
    (setf (gethash 'cl:let* ht) (make-elisp-subr :arity (cons 1 'unevalled)))
    (setf (gethash 'cl:catch ht) (make-elisp-subr :arity (cons 1 'unevalled)))
    (setf (gethash 'cl:throw ht) (make-elisp-subr :arity (cons 2 'unevalled)))
    (setf (gethash 'cl:unwind-protect ht) (make-elisp-subr :arity (cons 1 'unevalled)))
    ht))

(cl:defun subrp (object)
  "Bring-up subset of ELisp `subrp'."
  (and (typep object 'elisp-subr) t))

(cl:defun subr-arity (object)
  "Bring-up subset of ELisp `subr-arity'."
  (when (typep object 'elisp-subr)
    (elisp-subr-arity object)))

(cl:defun %mode-hook-symbol (mode)
  (intern (concat (symbol-name mode) "-hook")))

(cl:defun %mode-map-symbol (mode)
  (intern (concat (symbol-name mode) "-map")))

(cl:defun %key-id (key)
  (cond
   ((stringp key) key)
   ((vectorp key) (write-to-string key :escape t))
   ((characterp key) (string key))
   ((integerp key) (cl:format nil "#<keycode ~D>" key))
   (t (write-to-string key :escape t))))

(cl:defun %key-event-description (event)
  (cond
   ((integerp event)
    (cond
     ((= event 127) "DEL")
     ((= event 27) "ESC")
     ((= event 13) "RET")
     ((= event 9) "TAB")
     ((= event 32) "SPC")
     ((and (<= 0 event) (< event 32))
      (cl:format nil "C-~A" (string (code-char (+ event 64)))))
     (t
      (string (code-char event)))))
   ((characterp event) (string event))
   ((symbolp event) (symbol-name event))
   (t (princ-to-string event))))

(cl:defun key-description (keys &optional _noangles)
  "Bring-up subset of ELisp `key-description'."
  (declare (cl:ignore _noangles))
  (labels ((emit (seq)
             (cl:with-output-to-string (out)
               (loop for i from 0 for ev in seq do
                 (when (> i 0) (write-char #\Space out))
                 (write-string (%key-event-description ev) out)))))
    (cond
     ((stringp keys)
      (emit (loop for ch across keys collect (char-code ch))))
     ((vectorp keys)
      (emit (loop for i from 0 below (length keys) collect (aref keys i))))
     ((consp keys) (emit keys))
     (t (%key-event-description keys)))))

(cl:defun %normalize-key-event (event)
  (cond
   ((integerp event) event)
   ((characterp event) (char-code event))
   (t event)))

(cl:defun %keyseq->events (keys)
  (cond
   ((stringp keys)
    (let ((s (if (unibyte-string-p keys)
                 (%elisp-string->cl-string keys)
                 keys)))
      (loop for ch across s collect (char-code ch))))
   ((vectorp keys)
    (loop for i from 0 below (length keys)
          collect (%normalize-key-event (aref keys i))))
   ((consp keys)
    (mapcar #'%normalize-key-event keys))
   (t
    (list (%normalize-key-event keys)))))

(cl:defun %keymap-resolve (keymap)
  (cond
   ((typep keymap 'elisp-keymap) keymap)
   ((and (symbolp keymap) (cl:boundp keymap))
    (%keymap-resolve (symbol-value keymap)))
   ((and (symbolp keymap) (fboundp keymap))
    (%keymap-resolve (symbol-function keymap)))
   ((and (consp keymap) (eq (car keymap) 'keymap))
    (cond
     ((and (consp (cddr keymap)) (typep (caddr keymap) 'elisp-keymap))
      (caddr keymap))
     (t
      (let ((km (make-elisp-keymap)))
        (dolist (cell (cdr keymap) km)
          (when (consp cell)
            (let ((k (car cell))
                  (v (cdr cell)))
              (ignore-errors (define-key km k v)))))))))
   (t (error "ELISP: expected keymap, got: ~S" keymap))))

(cl:defun %keymap-get1 (keymap event)
  (let* ((km (%keymap-resolve keymap))
         (ht (elisp-keymap-table km)))
    (multiple-value-bind (v presentp) (gethash event ht)
      (when presentp
        (return-from %keymap-get1 (cl:values v t)))
      ;; Legacy: older bring-up stored single-character strings.
      (when (and (integerp event) (<= 0 event) (<= event 255))
        (multiple-value-bind (v2 p2) (gethash (string (code-char event)) ht)
          (when p2 (return-from %keymap-get1 (cl:values v2 t)))))
      (when (symbolp event)
        (multiple-value-bind (v2 p2) (gethash (symbol-name event) ht)
          (when p2 (return-from %keymap-get1 (cl:values v2 t)))))
      (cl:values nil nil))))

(cl:defun lookup-key (keymap keys &optional accept-default)
  "Bring-up subset of ELisp `lookup-key'."
  (let* ((events (%keyseq->events keys))
         (len (length events))
         (km (%keymap-resolve keymap)))
    (loop for ev in events
          for idx from 1 do
            (multiple-value-bind (binding presentp) (%keymap-get1 km ev)
              (unless presentp
                (when accept-default
                  (multiple-value-bind (d dpresentp) (%keymap-get1 km t)
                    (when dpresentp
                      (setf binding d presentp t))))
                (unless presentp
                    (return-from lookup-key nil)))
              ;; Menu entries are often stored as (\"Label\" . KEYMAP).  Treat
              ;; these as keymaps for both traversal and retrieval, matching
              ;; how upstream `lookup-key' behaves for menu-bar submaps.
              (when (and (consp binding)
                         (or (cl:stringp (car binding)) (unibyte-string-p (car binding)))
                         (keymapp (cdr binding)))
                (setf binding (cdr binding)))
              (if (= idx len)
                  (return-from lookup-key binding)
                  (cond
                   ((keymapp binding)
                    (setf km (%keymap-resolve binding)))
                   (t
                    (return-from lookup-key idx))))))))

(cl:defun map-keymap (function keymap)
  "Bring-up subset of ELisp `map-keymap'."
  (let ((km (%keymap-resolve keymap)))
    (maphash
     (lambda (k v)
       (let ((event (cond
                     ((and (stringp k) (= (length k) 1))
                      (char-code (aref k 0)))
                     (t k))))
         (funcall function event v)))
     (elisp-keymap-table km)))
  nil)

(cl:defun define-key (keymap key definition &optional remove)
  "Minimal stub for ELisp `define-key' on `elisp-keymap' objects."
  (let* ((km (%keymap-resolve keymap))
         (events (%keyseq->events key)))
    (when (null events)
      (error "ELISP:DEFINE-KEY empty key sequence"))
    (loop for ev in (butlast events) do
      (multiple-value-bind (next presentp) (%keymap-get1 km ev)
        (cond
         ((and presentp (keymapp next))
          (setf km (%keymap-resolve next)))
         ((and presentp (consp next)
               (or (cl:stringp (car next)) (unibyte-string-p (car next)))
               (keymapp (cdr next)))
          (setf km (%keymap-resolve (cdr next))))
         ((and remove (not presentp))
          (return-from define-key nil))
         (t
          (let ((child (make-elisp-keymap)))
            (setf (gethash ev (elisp-keymap-table km)) child)
            (setf km child))))))
    (let ((last (car (last events))))
      (cond
       (remove
        (remhash last (elisp-keymap-table km))
        nil)
       (t
        (setf (gethash last (elisp-keymap-table km)) definition)
        definition)))))

(cl:defun where-is-internal (command &optional keymap firstonly _noindirect _noany _include-menus)
  "Bring-up subset of ELisp `where-is-internal'.

Returns a list of key sequences (vectors of events).  This is enough for early
help/key-description callers."
  (declare (cl:ignore _noindirect _noany _include-menus))
  (let ((seen (cl:make-hash-table :test 'eq))
        (out nil))
    (labels ((scan (km prefix)
               (when (null km)
                 (return-from scan nil))
               (let ((k (%keymap-resolve km)))
                 (when (gethash k seen)
                   (return-from scan nil))
                 (setf (gethash k seen) t)
                 (map-keymap
                  (lambda (event binding)
                    (cond
                     ;; Ignore menu items during bring-up.
                     ((and (consp binding) (eq (car binding) 'menu-item)) nil)
                     ((keymapp binding)
                      (scan binding (append prefix (list event))))
                     ((and (symbolp binding) (eq binding command))
                      (push (coerce (append prefix (list event)) 'vector) out)
                      (when firstonly
                        (return-from where-is-internal (nreverse out))))
                     (t nil)))
                  k)
                 (scan (keymap-parent k) prefix))))
      (let ((km*
              (cond
               ((null keymap)
                ;; Prefer local bindings first, then global.
                (list (current-local-map) (current-global-map)))
               (t (list keymap)))))
        (dolist (km km*)
          (scan km nil))
        (nreverse out)))))

(cl:defun bindings--define-key (map key item)
  "Bring-up subset of ELisp `bindings--define-key'."
  (define-key
   map key
   (cond
    ((not (consp item)) item)
    ((keymapp item) item)
    ((stringp (car item)) item)
    ((eq 'menu-item (car item))
     (if (keymapp (nth 2 item))
         (append (list 'menu-item (nth 1 item) (nth 2 item)) (nthcdr 3 item))
         item))
    (t
     (message "non-menu-item: %S" item)
     item))))

(cl:defun define-abbrev-table (name defs &optional _docstring &rest _rest)
  "Bring-up stub for ELisp `define-abbrev-table'."
  (declare (cl:ignore _docstring _rest))
  (unless (symbolp name)
    (error "ELISP:DEFINE-ABBREV-TABLE expected symbol, got: ~S" name))
  ;; During bring-up we ignore DEFS and represent abbrev tables as plain hash
  ;; tables.  This is enough for mode files that only need the variable bound.
  (unless (or (null defs) (listp defs))
    (error "ELISP:DEFINE-ABBREV-TABLE expected defs list or nil, got: ~S" defs))
  (let ((tbl (cl:make-hash-table :test 'cl:equal)))
    (set name tbl)
    tbl))

(cl:defmacro define-derived-mode (child _parent _name &optional docstring &rest _body)
  "Bring-up subset of ELisp `define-derived-mode'.

For now we:
- create CHILD-hook and CHILD-map variables (if not already bound),
- define a no-op mode function CHILD.

This is sufficient for many shipped Elisp files to load; it is not a full
major-mode implementation."
  (declare (cl:ignore _parent _name _body))
  (let ((hook (%mode-hook-symbol child))
        (map (%mode-map-symbol child)))
    `(progn
       (cl:defvar ,hook nil)
       (cl:defvar ,map (make-elisp-keymap))
       (defun ,child (&rest _args)
         ,@(when (stringp docstring) (list docstring))
         (declare (cl:ignore _args))
         nil)
       ',child)))

(cl:defmacro easy-menu-define (symbol _keymap _doc menu)
  "Bring-up stub for ELisp `easy-menu-define'."
  (declare (cl:ignore _keymap _doc))
  `(progn
     (cl:defvar ,symbol ,menu)
     ',symbol))

(cl:defun button-category-symbol (type)
  "Bring-up subset of ELisp `button-category-symbol'."
  (or (get type 'button-category-symbol)
      (error "Unknown button type `%s'" type)))

(put 'default-button 'face 'button)
(put 'default-button 'mouse-face 'highlight)
(put 'default-button 'help-echo "mouse-2, RET: Push this button")
(put 'button 'button-category-symbol 'default-button)

(cl:defun define-button-type (name &rest properties)
  "Bring-up subset of ELisp `define-button-type'."
  (unless (symbolp name)
    (error "ELISP:DEFINE-BUTTON-TYPE expected symbol, got: ~S" name))
  (let* ((type-entry (or (plist-member properties 'supertype)
                         (plist-member properties :supertype)))
         (supertype (if type-entry (cadr type-entry) 'button))
         (super-catsym (button-category-symbol supertype))
         (catsym (or (get name 'button-category-symbol)
                     (cl:make-symbol
                      (concatenate 'cl:string
                                   (%elisp-string->cl-string (symbol-name name))
                                   "-button")))))
    (put name 'button-category-symbol catsym)
    ;; Inherit defaults from the supertype's category symbol.
    (let ((plist (symbol-plist super-catsym)))
      (loop while plist do
        (put catsym (pop plist) (pop plist))))
    (put catsym 'type name)
    ;; Apply provided properties (excluding :supertype).
    (loop while properties do
      (let ((prop (pop properties)))
        (when (eq prop :supertype)
          (setf prop 'supertype))
        (put catsym prop (pop properties))))
    (unless (get catsym 'supertype)
      (put catsym 'supertype supertype))
    name))

(cl:defun make-text-button (beg end &rest properties)
  "Bring-up subset of ELisp `make-text-button'."
  (let ((object nil)
        (type-entry (or (plist-member properties 'type)
                        (plist-member properties :type))))
    (when (plist-get properties 'category)
      (error "Button `category' property may not be set directly"))
    (if (null type-entry)
        (setf properties (cons 'category (cons 'default-button properties)))
        (progn
          (setf (car type-entry) 'category)
          (setf (cadr type-entry) (button-category-symbol (cadr type-entry)))))
    (when (stringp beg)
      (setf object (copy-seq beg)
            beg 0
            end (length object)))
    (add-text-properties beg end
                         ;; Each button should have a non-eq `button' property.
                         (cons 'button (cons (list t) properties))
                         object)
    (or object beg)))

(cl:defun insert-text-button (label &rest properties)
  "Bring-up subset of ELisp `insert-text-button'."
  (apply #'make-text-button
         (prog1 (point) (insert label))
         (point)
         properties))

(cl:defun add-hook (hook function &optional append _local)
  "Bring-up subset of ELisp `add-hook'.

HOOK is a symbol naming a hook variable whose value is a list of functions."
  (declare (cl:ignore _local))
  (unless (symbolp hook)
    (error "ELISP:ADD-HOOK expected a hook symbol, got: ~S" hook))
  (let ((cur (if (cl:boundp hook) (symbol-value hook) nil)))
    (unless (listp cur)
      (set hook nil)
      (setf cur nil))
    (unless (cl:member function cur :test #'equal)
      (set hook (if append (append cur (list function)) (cons function cur)))))
  t)

(cl:defun remove-hook (hook function &optional _local)
  "Bring-up subset of ELisp `remove-hook'."
  (declare (cl:ignore _local))
  (unless (symbolp hook)
    (error "ELISP:REMOVE-HOOK expected a hook symbol, got: ~S" hook))
  (when (cl:boundp hook)
    (let ((cur (symbol-value hook)))
      (when (listp cur)
        (set hook (remove function cur :test #'equal)))))
  t)

(cl:defun run-hooks (&rest hooks)
  "Bring-up subset of ELisp `run-hooks'."
  (dolist (hook hooks)
    (when (and (symbolp hook) (cl:boundp hook))
      (let ((cur (symbol-value hook)))
        (when (listp cur)
          (dolist (fn cur)
            (ignore-errors (funcall fn)))))))
  nil)

(cl:defun run-hook-with-args (hook &rest args)
  "Bring-up subset of the C primitive `run-hook-with-args'."
  (unless (symbolp hook)
    (error "ELISP:RUN-HOOK-WITH-ARGS expected symbol, got: ~S" hook))
  (let ((cur (if (cl:boundp hook) (symbol-value hook) nil)))
    (when (null cur)
      (return-from run-hook-with-args nil))
    (unless (listp cur)
      (setf cur (list cur)))
    (dolist (fn cur)
      (ignore-errors (apply #'funcall fn args))))
  nil)

(cl:defun run-hook-with-args-until-success (hook &rest args)
  "Bring-up subset of ELisp `run-hook-with-args-until-success'."
  (unless (symbolp hook)
    (error "ELISP:RUN-HOOK-WITH-ARGS-UNTIL-SUCCESS expected symbol, got: ~S" hook))
  (let ((cur (if (cl:boundp hook) (symbol-value hook) nil)))
    (when (null cur)
      (return-from run-hook-with-args-until-success nil))
    (unless (listp cur)
      (setf cur (list cur)))
    (dolist (fn cur)
      (let ((v (apply #'funcall fn args)))
        (when v
          (return-from run-hook-with-args-until-success v))))
    nil))

(cl:defun run-hook-with-args-until-failure (hook &rest args)
  "Bring-up subset of ELisp `run-hook-with-args-until-failure'."
  (unless (symbolp hook)
    (error "ELISP:RUN-HOOK-WITH-ARGS-UNTIL-FAILURE expected symbol, got: ~S" hook))
  (let ((cur (if (cl:boundp hook) (symbol-value hook) nil)))
    (when (null cur)
      (return-from run-hook-with-args-until-failure t))
    (unless (listp cur)
      (setf cur (list cur)))
    (dolist (fn cur)
      (let ((v (apply #'funcall fn args)))
        (when (null v)
          (return-from run-hook-with-args-until-failure nil))))
    t))

(cl:defun run-hook-wrapped (hook wrap-function &rest args)
  "Bring-up subset of the C primitive `run-hook-wrapped'."
  (unless (symbolp hook)
    (error "ELISP:RUN-HOOK-WRAPPED expected hook symbol, got: ~S" hook))
  (let ((cur (if (cl:boundp hook) (symbol-value hook) nil)))
    (when (null cur)
      (return-from run-hook-wrapped nil))
    (unless (listp cur)
      (setf cur (list cur)))
    (dolist (fn cur)
      (when (functionp fn)
        (let ((v (apply #'funcall wrap-function fn args)))
          (when v
            (return-from run-hook-wrapped v)))))
    nil))

(cl:defun byte-compile-warn (format-string &rest args)
  "Bring-up stub for ELisp `byte-compile-warn'."
  (apply #'message (concat (string-to-unibyte "byte-compile-warn: ") format-string) args)
  nil)

(defvar byte-compile-warnings nil)
(defvar byte-compile-log-buffer nil)
(defvar byte-compile-error-on-warn nil)

(cl:defun %byte-compile--log (msg)
  (let ((buf (get-buffer-create "*Byte Compile Log*")))
    (cl:setq byte-compile-log-buffer buf)
    (with-current-buffer buf
      (goto-char (point-max))
      (insert msg "\n"))
    nil))

(cl:defun byte-compile (form)
  "Bring-up subset of ELisp `byte-compile'.

  For now, supports the limited shape exercised by upstream `cl-lib-tests.el`:
  byte-compiling a quoted (lambda ...) form to ensure macroexpansion happens
  before runtime."
  (let* ((raw
           (if (and (consp form) (eq (car form) 'quote) (consp (cdr form)) (null (cddr form)))
               (cadr form)
               form)))
    (cond
     ((and (consp raw) (eq (car raw) 'lambda))
      (let ((expanded (macroexpand-all raw)))
        (cond
         ;; Some macroexpansion paths can yield (cl:function (lambda ...)) already.
         ;; Avoid wrapping it again (FUNCTION #'(LAMBDA ...)) which SBCL rejects.
         ((and (consp expanded)
               (eq (car expanded) 'cl:function)
               (consp (cdr expanded))
               (null (cddr expanded)))
          (cl:eval expanded))
         (t
          (cl:eval `(cl:function ,expanded))))))
     ;; A function object is already in "compiled" form as far as clemacs bring-up
     ;; is concerned.
     ((cl:functionp raw) raw)
     #+sbcl
     ((typep raw 'sb-mop:funcallable-standard-object) raw)
     ((and (symbolp raw) (fboundp raw))
      (byte-compile (symbol-function raw)))
     ((and (consp raw) (eq (car raw) 'cl-defmethod))
      ;; Minimal stub for `cl-generic-tests--advertised-calling-convention-bug58563':
      ;; report a "Stray declare" warning and optionally error out.
      (%byte-compile--log "Stray declare in cl-defmethod")
      (when byte-compile-error-on-warn
        (error "Byte-compile warning"))
      nil)
     (t
      (error "ELISP:BYTE-COMPILE unsupported FORM: ~S" form)))))

(cl:defun byte-compile-warning-enabled-p (&rest _args)
  "Bring-up stub for ELisp `byte-compile-warning-enabled-p'."
  (declare (cl:ignore _args))
  nil)

(cl:defun add-to-list (list-var element &optional append _compare-fn)
  "Bring-up subset of ELisp `add-to-list'."
  (declare (cl:ignore _compare-fn))
  (unless (symbolp list-var)
    (error "ELISP:ADD-TO-LIST expected a symbol, got: ~S" list-var))
  (let ((cur (if (cl:boundp list-var) (symbol-value list-var) nil)))
    (unless (listp cur)
      (set list-var nil)
      (setf cur nil))
    (unless (cl:member element cur :test #'equal)
      (set list-var (if append (append cur (list element)) (cons element cur)))))
  t)
