(in-package #:elisp)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (cl:require "SB-CLTL2"))

;; `with-output-to-string' is also a CL macro; shadow it so ELisp code resolves
;; to our compatibility macro instead of tripping SBCL's package lock.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (shadow '(with-output-to-string macroexpand macroexpand-1 elt)))

;; Upstream ELisp uses declaration specifiers that CL implementations don't know
;; about.  Declare them so SBCL doesn't spam style warnings during bring-up.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (declaim
   (declaration pure completion important-return-value
                side-effect-free error-free
                advertised-calling-convention obsolete)))

;; Some upstream ELisp assumes these are always bound (typically set by the
;; byte-compiler or load machinery).  Bind them to NIL for bring-up so
;; macroexpansion helpers (macroexp.el, pcase.el, etc.) don't trip UNBOUND.
(cl:defvar byte-compile-current-file nil)
(cl:defvar load-file-name nil)
(cl:defvar current-load-list nil)
(cl:defvar debugger nil)
(cl:defvar emacs-basic-display nil)
(cl:defvar fill-prefix nil)
(cl:defvar last-command nil)
(cl:defvar pre-redisplay-function 'ignore)
(cl:defvar overlay-arrow-variable-list nil)
(cl:defvar standard-display-table nil)
(cl:defvar buffer-display-table nil)
(cl:defvar window-system nil)
;; `disp-table.el` assumes this is a vector (it grows it on demand).
(cl:defvar glyph-table (make-array 32 :initial-element nil))
(cl:defvar text-property-default-nonsticky nil)
(cl:defvar comment-start-skip nil)
;; `ert-with-temp-file' (and friends) consult these during macroexpansion.
(cl:defvar coding-system-for-write nil)
(cl:defvar standard-output t)
;; Common command/key processing vars referenced early by upstream lisp/.
;; Bind to NIL for bring-up so loads don't spam UNBOUND warnings.
(cl:defvar quit-flag nil)
(cl:defvar prefix-arg nil)
(cl:defvar current-prefix-arg nil)
(cl:defvar defining-kbd-macro nil)
(cl:defvar last-command-event nil)
(cl:defvar last-input-event nil)
(cl:defvar unread-command-events nil)
(cl:defvar executing-kbd-macro nil)
(cl:defvar keyboard-translate-table nil)
(cl:defvar local-map nil)
(cl:defvar help-form nil)
(cl:defvar line-spacing nil)
(cl:defvar auto-window-vscroll t)
(cl:defvar xterm-mouse-mode nil)
(cl:defvar minibuffer-default-prompt-format nil)
(cl:defvar minibuffer-completion-table nil)
(cl:defvar minibuffer-completion-predicate nil)
(cl:defvar minibuffer-completing-file-name nil)
(cl:defvar *clemacs-minibuffer-active-p* nil)
(cl:defvar *clemacs-minibuffer-buffer* nil)
(cl:defvar *clemacs-minibuffer-prompt-end* nil)
(cl:defvar *clemacs-minibuffer-selected-window* nil)
(cl:defparameter +clemacs-minibuffer-buffer-name+ " *Minibuf-0*")
(cl:defparameter +clemacs-minibuffer-exit-tag+ 'clemacs--minibuffer-exit)
(cl:defvar history-delete-duplicates nil)
(cl:defvar history-length nil)
(cl:defvar syntax-propertize-function nil)
(cl:defvar major-mode nil)
(cl:defvar auto-mode-alist nil)
(cl:defvar magic-fallback-mode-alist nil)
(cl:defvar minor-mode-map-alist nil)
(cl:defvar auto-save-file-name-transforms nil)
(cl:defvar text-mode-map)
(cl:defvar load-path nil)
(cl:defvar load-file-rep-suffixes nil)
(cl:defvar temporary-file-directory "/tmp")
(cl:defvar small-temporary-file-directory "/tmp")
(cl:defvar process-environment
  #+sbcl (cl:copy-list (sb-ext:posix-environ))
  #-sbcl nil)
(cl:defvar page-delimiter
  (cl:concatenate 'cl:string "^" (cl:string #\Page)))
(cl:defvar pdumper--pure-pool nil)
(cl:defvar after-init-time nil)
(cl:defvar before-init-time nil)

(cl:defun pdumping-p ()
  "Bring-up stub for the C primitive `pdumping-p'.

clemacs does not (yet) support pdump; treat this as false, except when
`pdumper--pure-pool' is explicitly non-nil."
  (and (boundp 'pdumper--pure-pool) pdumper--pure-pool t))

(cl:defvar *clemacs--next-translation-table-id* 0)

(cl:defun define-translation-table (symbol &rest args)
  "Bring-up stub for ELisp `define-translation-table'.

Upstream `mule.el` registers translation tables in `translation-table-vector'.
For clemacs bring-up, store the table on SYMBOL and return a small id."
  (let ((table (car args)))
    (put symbol 'translation-table
         (if (consp table)
             (make-translation-table-from-alist table)
             table))
    (let ((next (or (and (boundp '*clemacs--next-translation-table-id*)
                         *clemacs--next-translation-table-id*)
                    0)))
      (cl:proclaim (list 'cl:special '*clemacs--next-translation-table-id*))
      (setf *clemacs--next-translation-table-id* (1+ next))
      (put symbol 'translation-table-id next)
      next)))

(cl:defun translate-region (start end table)
  "Bring-up subset of ELisp `translate-region' (Unicode-only)."
  (labels ((resolve-table (x)
             (cond
              ((cl:hash-table-p x) x)
              ((typep x 'elisp-char-table) x)
              ((symbolp x)
               (or (get x 'translation-table)
                   (error "ELISP:TRANSLATE-REGION no translation-table: %S" x)))
              ((consp x) (make-translation-table-from-alist x))
              (t (error "ELISP:TRANSLATE-REGION bad TABLE: %S" x))))
           (lookup (tab code)
             (cond
              ((cl:hash-table-p tab)
               (cl:gethash code tab))
              ((typep tab 'elisp-char-table)
               ;; clemacs char-tables are currently 0..65535 only.
               (if (and (integerp code) (<= 0 code) (< code 65536))
                   (%char-table-ref tab code)
                   nil))
              (t nil)))
           (emit-replacement (out rep)
             (cond
              ((null rep) nil)
              ((integerp rep) (write-char (%elisp-code->char rep) out))
              ((characterp rep) (write-char rep out))
              ((stringp rep) (write-string (%elisp-string->cl-string rep) out))
              ((vectorp rep)
               (dotimes (i (length rep))
                 (write-char (%elisp-code->char (aref rep i)) out)))
              ((consp rep)
               (dolist (x rep)
                 (write-char (%elisp-code->char x) out)))
              (t
               (error "ELISP:TRANSLATE-REGION bad replacement: %S" rep)))))
    (let* ((tab (resolve-table table))
           (chunk (buffer-substring start end))
           (translations 0)
           (out
             (cl:with-output-to-string (s)
               (dotimes (i (length chunk))
                 (let* ((ch (char chunk i))
                        (code (%elisp-char-code ch))
                        (rep (lookup tab code)))
                   (if rep
                       (progn
                         (incf translations)
                         (emit-replacement s rep))
                       (write-char ch s)))))))
      (when (plusp translations)
        (delete-region start end)
        (goto-char start)
        (insert out))
      translations)))

;; Variables that upstream ELisp assumes exist very early (often C-defined),
;; but which may not have been DEFVAR'd yet when we start loading a subset of
;; `lisp/` under clemacs.  Declaring them here keeps SBCL from emitting
;; undefined-variable warnings while we bootstrap.
(cl:defvar inhibit-point-motion-hooks nil)
(cl:defvar inhibit-file-name-handlers nil)
(cl:defvar inhibit-file-name-operation nil)
(cl:defvar buffer-undo-list nil)
(cl:defvar default-frame-alist nil)
(cl:defvar default-frame-scroll-bars nil)
(cl:defvar shell-file-name nil)
(cl:defvar command-history nil)
(cl:defvar window-persistent-parameters nil)
(cl:defvar focus-follows-mouse nil)
(cl:defvar mouse-autoselect-window nil)
(cl:defvar buffer-backed-up nil)
(cl:defvar baud-rate 9600)
(cl:defvar window-combination-limit nil)
(cl:defvar window-combination-resize nil)
(cl:defvar minibuffer-auto-raise nil)
(cl:defvar input-method-function nil)
(cl:defvar minibuffer-message-timeout 2)
(cl:defvar cursor-sensor-inhibit nil)
(cl:defvar scalable-fonts-allowed nil)
(cl:defvar composition-break-at-point nil)
(cl:defvar display-fill-column-indicator nil)
(cl:defvar display-fill-column-indicator-column t)
(cl:defvar display-fill-column-indicator-character nil)
(cl:defvar display-line-numbers nil)
(cl:defvar display-line-numbers-width nil)
(cl:defvar display-line-numbers-current-absolute t)
(cl:defvar display-line-numbers-widen t)
(cl:defvar display-line-numbers-major-tick 10)
(cl:defvar display-line-numbers-minor-tick 5)
(cl:defvar display-hourglass nil)
(cl:defvar hourglass-delay 1)
(cl:defvar resize-mini-windows t)
(cl:defvar display-raw-bytes-as-hex nil)

;; Bring-up: these are defined later in upstream ELisp (or in libraries we may
;; not load yet), but are referenced by early-startup code paths.
(cl:defvar inhibit-auto-fill nil)
(cl:defvar comint-file-name-prefix nil)
(cl:defvar comint-file-name-quote-list nil)
(cl:defvar isearch-forward nil)
(cl:defvar isearch-success nil)
(cl:defvar isearch-error nil)
(cl:defvar current-input-method nil)
(cl:defvar current-input-method-title nil)
(cl:defvar multi-isearch-file-list nil)
(cl:defvar multi-isearch-buffer-list nil)
(cl:defvar multi-isearch-next-buffer-function nil)
(cl:defvar multi-isearch-next-buffer-current-function nil)
(cl:defvar multi-isearch-current-buffer nil)
(cl:defvar minibuffer-history-isearch-message-overlay nil)

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; The CL reader does not parse Emacs's special float syntax (e.g.
  ;; 0.0e+NaN, 1.0e+INF), so these tokens read as symbols.  Bind a small set of
  ;; those symbols to SBCL float constants so upstream libraries/tests that use
  ;; these literals don't trip UNBOUND-VARIABLE during bring-up.
  ;;
  ;; NOTE: This is intentionally minimal and can be generalized later if/when
  ;; we start bringing up float-heavy test suites.
  #+sbcl
  (labels ((bind-special-float-literal (name value)
             (let ((sym (cl:intern name (find-package "ELISP"))))
               (cl:proclaim (list 'cl:special sym))
               (setf (cl:symbol-value sym) value)
               sym)))
    (bind-special-float-literal "1.0E+INF" sb-ext:double-float-positive-infinity)
    (bind-special-float-literal "-1.0E+INF" sb-ext:double-float-negative-infinity)
    (let ((qnan (sb-kernel:make-double-float #x7ff80000 0)))
      (cl:dolist (name '("0.0E+NAN" "-0.0E+NAN" "2.0E+NAN" "3.0E+NAN"))
        (bind-special-float-literal name qnan)))))

(cl:defmacro bound-and-true-p (var)
  "Bring-up subset of ELisp `bound-and-true-p'."
  `(and (cl:boundp ',var) ,var))

(cl:defun gettext (msgid)
  "Bring-up stub for ELisp `gettext' (no i18n)."
  msgid)

(cl:defun ngettext (singular plural n)
  "Bring-up stub for ELisp `ngettext' (no i18n)."
  (if (and (integerp n) (= n 1))
      singular
      plural))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Upstream `pcase.el` uses `pure`/`side-effect-free` symbol properties to
  ;; reason about predicates during macroexpansion (e.g. quote-branch
  ;; elimination in `pcase-tests-quote-optimization`).
  (cl:dolist (sym '(consp
                    symbolp
                    keywordp
                    stringp
                    vectorp
                    functionp
                    compiled-function-p
                    symbol-with-pos-p))
    (setf (get sym 'side-effect-free) t)
    (setf (get sym 'pure) t)
    (setf (get sym 'error-free) t)))

(cl:defvar *clemacs-interactive-capture* nil)

(cl:defun %interactive (&optional _spec _captured-spec)
  "Runtime marker for ELisp `(interactive ...)` forms.

This must *not* evaluate the interactive spec when called non-interactively.
We keep the spec as data so `interactive-form` / `call-interactively` can
recover it from function definitions (notably for lambdas)."
  (declare (cl:ignore _spec)
           (cl:ignorable _captured-spec))
  (when *clemacs-interactive-capture*
    (setf *clemacs-interactive-capture* _captured-spec)
    (throw 'clemacs--interactive-captured :captured))
  nil)

(cl:defmacro interactive (&rest spec)
  "Bring-up subset of ELisp `interactive'.

Expand into a runtime marker that preserves SPEC as data so the command-loop
helpers (`interactive-form`, `call-interactively`) can recover it."
  (let ((spec1 (if (consp spec) (car spec) nil)))
    `(%interactive ',spec1
                   (if *clemacs-interactive-capture*
                       ,spec1
                       nil))))

(cl:defun ding (&optional _arg)
  "Bring-up stub for ELisp `ding'."
  (declare (cl:ignore _arg))
  nil)

(cl:defun garbage-collect ()
  "Bring-up stub for ELisp `garbage-collect'."
  (ignore-errors (sb-ext:gc :full t))
  nil)

(cl:defmacro defvar (var &optional (init nil init-supplied-p) doc)
  "ELisp-ish DEFVAR.

Accepts unibyte/multibyte docstrings and coerces them to a CL string so SBCL
recognizes them as docstrings (keeping subsequent DECLARE forms legal)."
  (let ((doc* (and doc
                   (if (cl:stringp doc) doc (%elisp-string->cl-string doc)))))
    (cond
     ((and (not init-supplied-p) (null doc*))
      `(cl:defvar ,var))
     ((null doc*)
      `(cl:defvar ,var ,init))
     (t
      `(cl:defvar ,var ,init ,doc*)))))

(cl:defun special-variable-p (symbol)
  "Bring-up subset of the C primitive `special-variable-p'."
  (unless (symbolp symbol)
    (error "ELISP:SPECIAL-VARIABLE-P expected symbol, got: %S" symbol))
  (when (cl:gethash symbol *clemacs-force-non-special-vars*)
    (return-from special-variable-p nil))
  #+sbcl
  (eq (nth-value 0 (sb-cltl2:variable-information symbol)) :special)
  #-sbcl
  nil)

(cl:defvar *clemacs-force-non-special-vars* (cl:make-hash-table :test 'cl:eq))

(cl:defun internal--define-uninitialized-variable (symbol &optional doc)
  "Bring-up subset of the C primitive `internal--define-uninitialized-variable'."
  (unless (symbolp symbol)
    (error "ELISP:INTERNAL--DEFINE-UNINITIALIZED-VARIABLE expected symbol, got: %S" symbol))
  ;; Emacs marks the symbol as declared-special without affecting its current
  ;; value (which may be void/unbound).  In CL terms, proclaim it SPECIAL.
  #+sbcl (cl:proclaim (list 'cl:special symbol))
  (when doc
    (let ((doc* (if (cl:stringp doc) doc (%elisp-string->cl-string doc))))
      (put symbol 'variable-documentation doc*)))
  nil)

(cl:defun internal-make-var-non-special (symbol)
  "Bring-up stub for the C primitive `internal-make-var-non-special'."
  (unless (symbolp symbol)
    (error "ELISP:INTERNAL-MAKE-VAR-NON-SPECIAL expected symbol, got: %S" symbol))
  (setf (cl:gethash symbol *clemacs-force-non-special-vars*) t)
  nil)

(cl:defun version-list-not-zero (lst)
  "Bring-up subset of ELisp `version-list-not-zero'."
  (let ((xs lst))
    (cl:loop while (and xs (zerop (car xs))) do
      (setf xs (cdr xs)))
    (if xs (car xs) 0)))

(cl:defmacro dolist (spec &body body)
  "Bring-up subset of ELisp `dolist'."
  (destructuring-bind (var list-form &optional result) spec
    (unless (symbolp var)
      (error "ELISP:DOLIST expects a symbol var, got: %S" var))
    (let ((tail (cl:gensym "DOLIST-TAIL-")))
      `(cl:block nil
         (let ((,tail ,list-form)
               (,var nil))
           (cl:tagbody
            start
              (when (endp ,tail)
                (go end))
              (setf ,var (car ,tail))
              (setf ,tail (cdr ,tail))
              ,@body
              (go start)
            end)
           (setf ,var nil)
           ,result)))))

(cl:defun nlistp (object)
  "Bring-up subset of ELisp `nlistp'."
  (not (listp object)))

(cl:defun symbol-name (sym)
  "ELisp-ish SYMBOL-NAME that returns lowercase names by default."
  (let* ((pkg (cl:symbol-package sym))
         (raw (cl:symbol-name sym))
         ;; Most upstream ELisp source uses lowercase symbol spellings, but the
         ;; CL reader uppercases them.  Downcase interned symbols to approximate
         ;; ELisp, while preserving the case of uninterned symbols created via
         ;; `make-symbol' / `gensym'.
         (base (if (null pkg) raw (string-downcase raw)))
         (name
           (cond
            ;; In Emacs, (symbol-name :foo) => \":foo\".
            ((and pkg (eq pkg (find-package "KEYWORD")))
             (concatenate 'cl:string ":" base))
            ;; Emacs Lisp has no CL package prefixes, but clemacs uses CL
            ;; packages as a bring-up hack for symbols like GUI:bottom; preserve
            ;; the original surface spelling for those.
            ((and pkg
                  (not (eq pkg (find-package "ELISP")))
                  (not (eq pkg (find-package "CL"))))
             (concatenate 'cl:string
                          (string-downcase (cl:package-name pkg))
                          ":"
                          base))
            (t base))))
    ;; Emacs returns unibyte strings for ASCII-only symbol names.
    (if (every (lambda (ch) (< (char-code ch) 128)) name)
        (let ((out (%make-unibyte-string (length name))))
          (dotimes (i (length name))
            (setf (aref out i) (char-code (char name i))))
          out)
        name)))

(cl:defun elt (sequence n)
  "ELisp-ish `elt' for lists/vectors/strings.

Unlike CL:ELT, indexing a string returns an integer character code."
  (unless (integerp n)
    (signal 'wrong-type-argument (list 'integerp n)))
  (when (minusp n)
    (signal 'args-out-of-range (list sequence n)))
  (cond
   ((unibyte-string-p sequence) (aref sequence n))
   ((cl:stringp sequence) (%elisp-char-code (char sequence n)))
   (t (cl:elt sequence n))))

(cl:defun length> (sequence n)
  "Return non-nil if SEQUENCE has length greater than N."
  (unless (integerp n)
    (signal 'wrong-type-argument (list 'integerp n)))
  (when (minusp n)
    (cl:return-from length> t))
  (cond
   ((listp sequence)
    (let ((remaining n)
          (tail sequence))
      (cl:loop
        (cond
         ((null tail) (cl:return nil))
         ((consp tail)
          (decf remaining)
          (when (minusp remaining)
            (cl:return t))
          (setf tail (cdr tail)))
         (t
          (signal 'wrong-type-argument (list 'listp sequence)))))))
   (t
    (> (cl:length sequence) n))))

(cl:defun length< (sequence n)
  "Return non-nil if SEQUENCE has length less than N."
  (unless (integerp n)
    (signal 'wrong-type-argument (list 'integerp n)))
  (when (<= n 0)
    (cl:return-from length< nil))
  (cond
   ((listp sequence)
    (let ((remaining n)
          (tail sequence))
      (cl:loop
        (cond
         ((null tail) (cl:return t))
         ((consp tail)
          (decf remaining)
          (when (zerop remaining)
            (cl:return nil))
          (setf tail (cdr tail)))
         (t
          (signal 'wrong-type-argument (list 'listp sequence)))))))
   (t
    (< (cl:length sequence) n))))

(cl:defun length= (sequence n)
  "Return non-nil if SEQUENCE has length equal to N."
  (unless (integerp n)
    (signal 'wrong-type-argument (list 'integerp n)))
  (when (minusp n)
    (cl:return-from length= nil))
  (cond
   ((listp sequence)
    (let ((remaining n)
          (tail sequence))
      (cl:loop
        (cond
         ((null tail) (cl:return (zerop remaining)))
         ((consp tail)
          (when (zerop remaining)
            (cl:return nil))
          (decf remaining)
          (setf tail (cdr tail)))
         (t
          (signal 'wrong-type-argument (list 'listp sequence)))))))
   (t
    (= (cl:length sequence) n))))

(cl:defun take (n list)
  "Return a list of the first N elements of LIST.

If N is zero or negative, return nil.  Always returns a fresh list."
  (unless (integerp n)
    (signal 'wrong-type-argument (list 'integerp n)))
  (unless (listp list)
    (signal 'wrong-type-argument (list 'listp list)))
  (let ((n (max n 0))
        (out nil)
        (xs list))
    (loop while (and (> n 0) (consp xs)) do
      (push (car xs) out)
      (setf xs (cdr xs))
      (decf n))
    (nreverse out)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Some upstream ELisp (notably regexp-opt.el) uses `string-lessp'.  If we
  ;; leave this unshadowed, the ELISP package inherits CL:STRING-LESSP, which
  ;; doesn't accept our unibyte string representation.
  (cl:shadow 'string-lessp (find-package "ELISP"))
  ;; Emacs `compiled-function-p' checks for byte-code / native-compiled
  ;; *ELisp* functions.  In clemacs bring-up, our `lambda' currently yields a
  ;; host function object, so we must not inherit CL:COMPILED-FUNCTION-P here.
  (cl:shadow 'compiled-function-p (find-package "ELISP"))
  ;; These exist in CL too; shadow them so we can provide ELisp semantics
  ;; without tripping SBCL package locks.
  (cl:shadow 'assoc (find-package "ELISP"))
  (cl:shadow 'rassoc (find-package "ELISP")))

(cl:defun compiled-function-p (_object)
  "Bring-up stub for ELisp `compiled-function-p'."
  (declare (cl:ignore _object))
  nil)

(cl:defun byte-code-function-p (_object)
  "Bring-up stub for ELisp `byte-code-function-p'."
  (declare (cl:ignore _object))
  nil)

(cl:defun car-less-than-car (a b)
  "Bring-up subset of ELisp `car-less-than-car'."
  (cl:< (cl:car a) (cl:car b)))

(cl:defun string-lessp (s1 s2 &optional _start1 _end1 _start2 _end2)
  "Bring-up subset of ELisp `string-lessp'."
  (declare (cl:ignore _start1 _end1 _start2 _end2))
  (unless (and (stringp s1) (stringp s2))
    (error "ELISP:STRING-LESSP expects strings, got: %S %S" s1 s2))
  (cl:string< (%elisp-string->cl-string s1)
              (%elisp-string->cl-string s2)))

(cl:defvar completion-ignore-case nil)
(cl:defvar completion-regexp-list nil)
(cl:defvar minibuffer-allow-text-properties nil)

(cl:defun %completion--prefix-match-p (prefix candidate)
  (let ((n (length prefix)))
    (and (<= n (length candidate))
         (if completion-ignore-case
             (cl:string-equal prefix candidate :end1 n :end2 n)
             (cl:string= prefix candidate :end1 n :end2 n)))))

(cl:defun %completion--regexp-list-match-p (candidate)
  (let ((regs completion-regexp-list))
    (cond
     ((null regs) t)
     ((not (listp regs)) t)
     ((not (fboundp 'string-match-p)) t)
     (t
      (dolist (re regs t)
        (when (and re (stringp re))
          (unless (string-match-p re candidate)
            (return nil))))))))

(cl:defun %completion--concat2 (a b)
  (cond
   ;; If either side is a CL string, produce a CL string result.  This avoids
   ;; trying to stuff unibyte octets into (array character) when callers
   ;; preserve typed prefix text from a multibyte buffer substring.
   ((or (cl:stringp a) (cl:stringp b))
    (concatenate 'cl:string (%elisp-string->cl-string a) (%elisp-string->cl-string b)))
   ((and (unibyte-string-p a) (unibyte-string-p b))
    (let* ((alen (length a))
           (blen (length b))
           (out (make-array (+ alen blen) :element-type (array-element-type a))))
      (cl:replace out a :start1 0 :start2 0 :end2 alen)
      (cl:replace out b :start1 alen :start2 0 :end2 blen)
      out))
   (t
    (concatenate 'cl:string (%elisp-string->cl-string a) (%elisp-string->cl-string b)))))

(cl:defun %completion--copy-subseq (s start end)
  (cond
   ((unibyte-string-p s)
    (let* ((len (- end start))
           (out (%make-unibyte-string len)))
      (dotimes (i len)
        (setf (aref out i) (aref s (+ start i))))
      out))
   (t
    (subseq (copy-seq s) start end))))

(cl:defun try-completion (string collection &optional _predicate)
  "Bring-up subset of the C primitive `try-completion'.

This supports COLLECTION as either:
- a list of strings, or
- a functional completion table (STRING PREDICATE ACTION)."
  (unless (stringp string)
    (error "ELISP:TRY-COMPLETION expects STRING, got: %S" string))
  (when (functionp collection)
    (return-from try-completion (funcall collection string _predicate nil)))
  (unless (listp collection)
    (error "ELISP:TRY-COMPLETION only supports list collections, got: %S" collection))
  (let* ((prefix (%elisp-string->cl-string string))
         ;; Store (ELISP-STRING . CL-STRING) pairs so we can preserve the
         ;; original string type (unibyte vs multibyte) in the return value.
         (cands nil)
         (pred _predicate))
    (dolist (s collection)
      (when (and (stringp s)
                 (or (null pred)
                     (not (functionp pred))
                     (funcall pred s)))
        (let ((cs (%elisp-string->cl-string s)))
          (when (and (%completion--prefix-match-p prefix cs)
                     (%completion--regexp-list-match-p s))
            (push (cons s cs) cands)))))
    (when (null cands)
      (return-from try-completion nil))
    (setf cands (nreverse cands))
    ;; NOTE: completion tables are sets; repeated candidates should behave like
    ;; a single entry.  In particular, if every candidate is already exactly
    ;; PREFIX, Emacs returns T (even with duplicates in COLLECTION).
    (when (cl:every (lambda (c) (cl:string= (cdr c) prefix)) cands)
      (return-from try-completion t))
    (let* ((test (if completion-ignore-case #'char-equal #'char=))
           (multiplep (and (consp cands) (consp (cdr cands))))
           (s0 (caar cands))
           (cs0 (cdar cands))
           (common-len (length cs0)))
      (dolist (c (cdr cands))
        (let* ((cs (cdr c))
               (end2 (min common-len (length cs)))
               (n (mismatch cs0 cs :end1 common-len :end2 end2 :test test)))
          (when n
            (setf common-len (min common-len n)))))
      (let ((common (%completion--copy-subseq s0 0 common-len)))
        ;; When completing while ignoring case, prefer to preserve the user's
        ;; already-typed text, rather than switching its case to match the first
        ;; completion (e.g. bug#4219 / completion-pcm bug#38458).
        (let ((typed-len (length string)))
          (if (and completion-ignore-case
                   multiplep
                   (> typed-len 0)
                   (> common-len typed-len))
              (%completion--concat2 (%completion--copy-subseq string 0 typed-len)
                                    (%completion--copy-subseq common typed-len common-len))
            common))))))

(cl:defun all-completions (string collection &optional _predicate)
  "Bring-up subset of the C primitive `all-completions'.

This supports COLLECTION as either:
- a list of strings, or
- a functional completion table (STRING PREDICATE ACTION)."
  (unless (stringp string)
    (error "ELISP:ALL-COMPLETIONS expects STRING, got: %S" string))
  (when (functionp collection)
    (return-from all-completions (funcall collection string _predicate t)))
  (unless (listp collection)
    (error "ELISP:ALL-COMPLETIONS only supports list collections, got: %S" collection))
  (let* ((prefix (%elisp-string->cl-string string))
         (out nil)
         (pred _predicate))
    (dolist (s collection)
      (when (and (stringp s)
                 (or (null pred)
                     (not (functionp pred))
                     (funcall pred s)))
        (let ((cs (%elisp-string->cl-string s)))
          (when (and (%completion--prefix-match-p prefix cs)
                     (%completion--regexp-list-match-p s))
            (push s out)))))
    (nreverse out)))

(cl:defun test-completion (string collection &optional _predicate)
  "Bring-up subset of the C primitive `test-completion'."
  (unless (stringp string)
    (error "ELISP:TEST-COMPLETION expects STRING, got: %S" string))
  (when (functionp collection)
    (return-from test-completion (and (funcall collection string _predicate 'lambda) t)))
  (unless (listp collection)
    (error "ELISP:TEST-COMPLETION only supports list collections, got: %S" collection))
  (let ((pred _predicate)
        (target (%elisp-string->cl-string string)))
    (dolist (s collection)
      (when (and (stringp s)
                 (let ((cs (%elisp-string->cl-string s)))
                   (if completion-ignore-case
                       (cl:string-equal target cs)
                       (cl:string= target cs)))
                 (or (null pred)
                     (not (functionp pred))
                     (funcall pred s)))
        (return-from test-completion t))))
  nil)

(cl:defun completion-table-dynamic (fun &optional _switch-buffer)
  "Bring-up subset of ELisp `completion-table-dynamic'.

Return a functional completion table that calls FUN to produce the current
collection.  This is normally defined in `lisp/minibuffer.el`, but some
libraries (e.g. `lisp/progmodes/elisp-mode.el`) reference it before we reach the
`minibuffer.el` checkpoint in the `tty-editor` bring-up manifest."
  (declare (cl:ignore _switch-buffer))
  (unless (functionp fun)
    (error "ELISP:COMPLETION-TABLE-DYNAMIC expects function FUN, got: %S" fun))
  (lambda (string predicate action)
    (let ((collection (funcall fun string)))
      (cond
       ((eq action t) (all-completions string collection predicate))
       ((eq action 'lambda) (test-completion string collection predicate))
       ;; Unknown ACTION: be permissive during bring-up; behave like no matches.
       ((and action (not (null action))) nil)
       (t (try-completion string collection predicate))))))

(cl:defun assoc-string (key list &optional case-fold)
  "Bring-up subset of ELisp `assoc-string'."
  (unless (stringp key)
    (error "ELISP:ASSOC-STRING expects string key, got: %S" key))
  (let* ((k (%elisp-string->cl-string key))
         (fold (and case-fold t)))
    (cl:dolist (elt list)
      (cond
       ((and (consp elt) (stringp (car elt)))
        (let ((cs (%elisp-string->cl-string (car elt))))
          (when (if fold (cl:string-equal k cs) (cl:string= k cs))
            (return-from assoc-string elt))))
       ((stringp elt)
        (let ((cs (%elisp-string->cl-string elt)))
          (when (if fold (cl:string-equal k cs) (cl:string= k cs))
            (return-from assoc-string elt))))))
    nil))

(cl:defvar *clemacs-obarray-tables*
  (cl:make-hash-table :test 'cl:eq)
  "Map obarray vectors to backing hash tables (string -> symbol).")

(cl:defun obarray-make (size)
  "Bring-up subset of the C primitive `obarray-make'.

Return a fresh obarray vector of SIZE, suitable for passing as the OBARRAY
argument to `intern'/`intern-soft'."
  (unless (and (integerp size) (> size 0))
    (error "ELISP:OBARRAY-MAKE expects positive integer SIZE, got: %S" size))
  (let ((v (make-array size :initial-element nil)))
    (setf (gethash v *clemacs-obarray-tables*)
          (cl:make-hash-table :test 'cl:equal))
    v))

(cl:defun %intern-obarray-table (obarray)
  (unless (vectorp obarray)
    (error "ELISP: expected obarray vector, got: %S" obarray))
  (or (gethash obarray *clemacs-obarray-tables*)
      (setf (gethash obarray *clemacs-obarray-tables*)
            (cl:make-hash-table :test 'cl:equal))))

(cl:defun intern (name &optional obarray)
  "ELisp-ish INTERN.

Supports:
- NAME as a string (including unibyte strings) or a symbol.
- OBARRAY as either:
  - nil (intern into the ELISP package; pragmatic compatibility), or
  - an obarray vector created by `obarray-make' (intern into that obarray), or
  - a CL package designator (legacy clemacs convenience; not used by upstream ELisp)."
  (when (symbolp name)
    (return-from intern name))
  (unless (stringp name)
    (error "ELISP:INTERN expects NAME as string or symbol, got: %S" name))
  (cond
   ;; Legacy clemacs behavior: allow passing an explicit CL package.
   ((or (null obarray)
        (typep obarray 'package)
        (and (symbolp obarray) (find-package obarray))
        (and (cl:stringp obarray) (find-package obarray)))
    (let ((pkg (cond
                ((null obarray) (find-package "ELISP"))
                ((typep obarray 'package) obarray)
                (t (find-package obarray)))))
      (cl:intern (string-upcase (%elisp-string->cl-string name)) pkg)))
   ;; Emacs-style: obarray vector.
   ((vectorp obarray)
    (let* ((k (%elisp-string->cl-string name))
           (tab (%intern-obarray-table obarray))
           (sym (gethash k tab)))
      (or sym
          (setf (gethash k tab) (cl:make-symbol k)))))
   (t
    (error "ELISP:INTERN unsupported OBARRAY: %S" obarray))))

(cl:defun intern-soft (name &optional obarray)
  "Bring-up subset of ELisp `intern-soft'."
  (unless (stringp name)
    (error "ELISP:INTERN-SOFT expects a string, got: ~S" name))
  (cond
   ((null obarray)
    (multiple-value-bind (sym status)
        (find-symbol (string-upcase (%elisp-string->cl-string name)) (find-package "ELISP"))
      (declare (cl:ignore status))
      sym))
   ((vectorp obarray)
    (gethash (%elisp-string->cl-string name) (%intern-obarray-table obarray)))
   ;; Legacy clemacs behavior: allow passing an explicit CL package.
   ((or (typep obarray 'package)
        (and (symbolp obarray) (find-package obarray))
        (and (cl:stringp obarray) (find-package obarray)))
    (let ((pkg (cond
                ((typep obarray 'package) obarray)
                (t (find-package obarray)))))
      (multiple-value-bind (sym status)
          (find-symbol (string-upcase (%elisp-string->cl-string name)) pkg)
        (declare (cl:ignore status))
        sym)))
   (t
    (error "ELISP:INTERN-SOFT unsupported OBARRAY: %S" obarray))))

(cl:defun make-symbol (name)
  "ELisp-ish MAKE-SYMBOL."
  (unless (stringp name)
    (error "ELISP:MAKE-SYMBOL expects a string, got: ~S" name))
  (cl:make-symbol (%elisp-string->cl-string name)))

(cl:defun gensym (&optional x)
  "ELisp-ish GENSYM.

Accepts a numeric counter or a string prefix (including unibyte strings)."
  (cond
   ((null x) (cl:gensym))
   ((integerp x) (cl:gensym x))
   ((stringp x) (cl:gensym (%elisp-string->cl-string x)))
   ((symbolp x) (cl:gensym (%elisp-string->cl-string (symbol-name x))))
   (t (error "ELISP:GENSYM unsupported arg: ~S" x))))

(cl:defun ignore (&rest _args)
  "ELisp `ignore': ignore ARGS and return nil."
  (declare (cl:ignore _args))
  nil)

(cl:defun mapatoms (function &optional _obarray)
  "Bring-up subset of ELisp `mapatoms'.

Emacs iterates the current obarray; for bring-up we approximate this by
iterating all symbols accessible in the ELISP package."
  (declare (cl:ignore _obarray))
  (let ((pkg (find-package "ELISP")))
    (do-symbols (s pkg)
      (cl:funcall function s)))
  nil)

(cl:defmacro function (&environment env arg)
  "ELisp-ish FUNCTION.

Emacs Lisp's `function' special form is more of a \"function designator\"
than a strict CL:FUNCTION: for symbols, it yields the symbol (resolved later
by `funcall' / `apply').  For lambdas, return a real CL function object so
upstream macroexpanders can safely parse lambda lists/bodies."
  (cond
   ((symbolp arg)
    (multiple-value-bind (_kind localp _decls)
        (sb-cltl2:function-information arg env)
      (declare (cl:ignore _kind _decls))
      ;; If there's a local function binding (e.g. `cl-labels' / `labels'),
      ;; preserve it by producing a real CL function object.  Otherwise keep
      ;; the ELisp behavior where symbols act as function designators.
      (if localp
          `(cl:function ,arg)
          `(quote ,arg))))
   ((and (consp arg) (eq (car arg) 'lambda))
    ;; In ELisp, (function (lambda ...)) evaluates to a closure.
    ;; Keep this as a real CL function object so upstream `macroexpand` users
    ;; (notably `cl-generic`) see `#'(lambda ...)` rather than a quoted lambda
    ;; list and can safely parse the lambda list/body.
    `(cl:function ,arg))
   ((and (consp arg) (eq (car arg) '|,|) (null (cddr arg)))
    (cadr arg))
   ((and (consp arg) (eq (car arg) '|,@|) (null (cddr arg)))
    (cadr arg))
   (t
     `(quote ,arg))))

(defvar *elisp-function-cells* (cl:make-hash-table :test 'eq))

(cl:defun symbol-function (symbol)
  "ELisp-ish SYMBOL-FUNCTION.

Returns NIL if SYMBOL has no function cell value."
  (multiple-value-bind (value presentp)
      (gethash symbol *elisp-function-cells*)
    (cond
     (presentp value)
     ((cl:macro-function symbol)
      ;; Expose CL-defined macros as ELisp macro objects `(macro . EXPANDER)`,
      ;; where EXPANDER is called with macro arguments (cdr of the macro form).
      ;; This shape is important for `nadvice` which advises macro expanders by
      ;; mutating the macro object (via (cdr (symbol-function ...))).
      (let* ((mf (cl:macro-function symbol))
             (cell
               (cons 'macro
                     (lambda (&rest args)
                       (funcall mf (cons symbol args) nil)))))
        (setf (gethash symbol *elisp-function-cells*) cell)
        cell))
     ((cl:fboundp symbol) (cl:symbol-function symbol))
     (t nil))))

(cl:defun fboundp (symbol)
  "ELisp-ish FBOUNDP."
  (multiple-value-bind (value presentp)
      (gethash symbol *elisp-function-cells*)
    (if presentp
        (not (null value))
        (cl:fboundp symbol))))

(cl:defun functionp (object)
  "Bring-up subset of ELisp `functionp'."
  (cond
   ;; In ELisp, symbols can denote functions via their function cell.
   ((symbolp object) (and (fboundp object) t))
   ;; ELisp lambda forms are callable objects.
   ((and (consp object) (eq (car object) 'lambda)) t)
   ;; Macro objects and autoload markers are treated as callable in the places
   ;; we care about during bring-up.
   ((and (consp object) (eq (car object) 'macro)) t)
   ((and (consp object) (eq (car object) 'autoload)) t)
   ;; OClosures (SBCL funcallable instances) are callable ELisp objects, used
   ;; heavily by `nadvice` and `add-function`.
   ((ignore-errors (typep object 'oclosure)) t)
   ;; Host function objects.
   ((cl:functionp object) t)
   (t nil)))

(cl:defun function-alias-p (symbol)
  "Bring-up subset of ELisp `function-alias-p'.

Returns a list of alias targets for SYMBOL's function cell, following chains
like: (defalias 'string= 'string-equal)."
  (unless (symbolp symbol)
    (return-from function-alias-p nil))
  (let ((seen (list symbol))
        (cur symbol)
        (out nil))
    (loop repeat 16 do
      (let ((next (handler-case
                      (symbol-function cur)
                    (elisp-signal (e)
                      (if (eq (elisp-signal-symbol e) 'void-function)
                          nil
                          (cl:error e))))))
        (unless (and (symbolp next) (not (eq next cur)))
          (return (nreverse out)))
        (when (cl:member next seen :test #'eq)
          (return (nreverse out)))
        (push next seen)
        (push next out)
        (setf cur next)))))

(cl:defun %resolve-function (fn &key (max-hops 16))
  (loop with cur = fn
        for hop from 0 below max-hops do
          (cond
           ((cl:functionp cur) (return cur))
           #+sbcl
           ((typep cur 'sb-mop:funcallable-standard-object) (return cur))
           ((and (consp cur) (eq (car cur) 'lambda))
            (return (cl:eval `(cl:function ,cur))))
           ((and (consp cur) (eq (car cur) 'autoload))
            (let ((next (autoload-do-load cur)))
              (when (and (consp next) (eq (car next) 'autoload))
                (error "ELISP: unresolved autoload: ~S" cur))
              (setf cur next)))
           ((symbolp cur)
            (let ((next (symbol-function cur)))
              (when (null next)
                (signal 'void-function (list cur)))
              (cond
               ((and (consp next) (eq (car next) 'autoload))
                (let ((loaded (autoload-do-load next cur)))
                  (when (and (consp loaded) (eq (car loaded) 'autoload))
                    (error "ELISP:AUTOLOAD failed to load function %S from %S"
                           cur (cadr next)))
                  (setf cur loaded)))
               (t
                (setf cur next)))))
           (t
            (error "ELISP: function cell is not callable: ~S" cur)))
        finally
          (error "ELISP: function indirection loop for ~S" fn)))

(cl:defun funcall (fn &rest args)
  "ELisp-ish FUNCALL that accepts symbols and lambda forms."
  (cl:apply (%resolve-function fn) args))

(cl:defun apply (fn &rest args)
  "ELisp-ish APPLY.

Supports the Emacs extension where `(apply (list FN ARG...))` is equivalent to
`(funcall FN ARG...)`."
  (cond
   ;; Emacs extension: single list arg interpreted as (FN . ARGS).
   ((and (null args) (consp fn))
    (cl:apply (%resolve-function (car fn)) (cdr fn)))
   ;; Standard shape: (apply FN ARG... LIST)
   (t
    (when (null args)
      (error "ELISP:APPLY expects at least 2 arguments"))
    (let* ((tail (car (cl:last args)))
           (prefix (cl:butlast args)))
      (unless (listp tail)
        (signal 'wrong-type-argument (list 'listp tail)))
      (cl:apply (%resolve-function fn) (cl:append prefix tail))))))

(cl:defun eval (form &optional lexical)
  "ELisp-ish EVAL.

ELisp `eval' accepts an optional LEXICAL argument.

For bring-up, support the common internal representation where LEXICAL is an
alist of (SYMBOL . VALUE) pairs; bind those symbols dynamically for the
duration of the evaluation."
  (cond
   ((and (consp lexical) (listp lexical))
    (let ((lets nil))
      (dolist (cell lexical)
        (when (and (consp cell) (symbolp (car cell)))
          (push (list (car cell) (cdr cell)) lets)))
      (cl:eval (%elisp-rewrite `(let ,(nreverse lets) ,form)))))
   (t
    (cl:eval (%elisp-rewrite form)))))

(cl:defun sxhash-equal (object)
  "Compatibility shim for the C primitive `sxhash-equal'."
  (cl:sxhash object))

(cl:defun % (x y)
  "Bring-up subset of ELisp `%'."
  (unless (and (integerp x) (integerp y))
    (error "ELISP:% expects integers, got: ~S ~S" x y))
  (cl:rem x y))

(cl:defun logand (&rest args)
  "Bring-up subset of ELisp `logand'.

In upstream ELisp, type errors are reported as `wrong-type-argument'.  Provide
an ELisp-shaped wrapper so callers like `cl-oddp'/'cl-evenp' signal the expected
error type when given non-integers."
  (cl:dolist (a args)
    (unless (integerp a)
      (signal 'wrong-type-argument (list 'integerp a))))
  (cl:apply #'cl:logand args))

(defconstant +char-table-size+ 65536)

(cl:defstruct (elisp-char-table
               (:constructor %make-elisp-char-table (type default data extra parent)))
  (type nil :type t)
  (default nil :type t)
  (data (make-array +char-table-size+ :initial-element nil) :type simple-vector)
  (extra (make-array 0 :adjustable t :fill-pointer 0) :type vector)
  (parent nil :type t))

(cl:defun %char-table-ref (table idx)
  (unless (and (integerp idx) (<= 0 idx) (< idx +char-table-size+))
    (error "ELISP: char-table index out of range: ~S" idx))
  (let ((val (svref (elisp-char-table-data table) idx)))
    (cond
     ((not (null val)) val)
     ((not (null (elisp-char-table-parent table)))
      (%char-table-ref (elisp-char-table-parent table) idx))
     (t (elisp-char-table-default table)))))

(cl:defun %char-table-set (table idx value)
  (unless (and (integerp idx) (<= 0 idx) (< idx +char-table-size+))
    (error "ELISP: char-table index out of range: ~S" idx))
  (setf (svref (elisp-char-table-data table) idx) value)
  value)

(cl:defun set-char-table-range (table range value)
  "Bring-up subset of ELisp `set-char-table-range'."
  (unless (char-table-p table)
    (error "ELISP:SET-CHAR-TABLE-RANGE expects a char-table, got: ~S" table))
  (cond
   ((eq range t)
    (setf (elisp-char-table-default table) value)
    value)
   ((integerp range)
    (%char-table-set table range value))
   ((characterp range)
    (%char-table-set table (char-code range) value))
   ((and (consp range) (integerp (car range)) (integerp (cdr range)))
    (let ((from (car range))
          (to (cdr range)))
      (when (> from to)
        (error "ELISP:SET-CHAR-TABLE-RANGE bad range: ~S" range))
      ;; clemacs currently models char-tables as fixed-size vectors of
      ;; +CHAR-TABLE-SIZE+ entries.  Clamp Emacs's broader Unicode ranges.
      (when (>= from +char-table-size+)
        (return-from set-char-table-range value))
      (when (>= to +char-table-size+)
        (setf to (1- +char-table-size+)))
      (loop for i from from to to do
        (%char-table-set table i value))
      value))
   (t
    (error "ELISP:SET-CHAR-TABLE-RANGE bad range: ~S" range))))

(cl:defun map-char-table (function table)
  "Bring-up subset of ELisp `map-char-table'."
  (unless (char-table-p table)
    (error "ELISP:MAP-CHAR-TABLE expects a char-table, got: ~S" table))
  (let ((default (elisp-char-table-default table)))
    (labels ((emit (start end val)
               (when (and start end (not (cl:equal val default)))
                 (funcall function
                          (if (= start end) start (cons start end))
                          val))))
      (let ((run-start 0)
            (run-val (%char-table-ref table 0)))
        (loop for i from 1 below +char-table-size+ do
          (let ((v (%char-table-ref table i)))
            (unless (cl:equal v run-val)
              (emit run-start (1- i) run-val)
              (setf run-start i
                    run-val v))))
        (emit run-start (1- +char-table-size+) run-val))))
  nil)

(cl:defun aref (array idx)
  "ELisp-ish AREF.

For strings, return a character code integer (Emacs Lisp semantics)."
  (cond
   ((typep array 'elisp-char-table) (%char-table-ref array idx))
   ((unibyte-string-p array) (cl:aref array idx))
   ((cl:stringp array) (%elisp-char-code (cl:aref array idx)))
   (t (cl:aref array idx))))

(cl:defun (setf aref) (value array idx)
  "Set ARRAY element IDX to VALUE and return VALUE (ELisp-ish)."
  (cond
   ((typep array 'elisp-char-table)
    (%char-table-set array idx value))
   ((unibyte-string-p array)
    (unless (and (integerp value) (<= 0 value 255))
      (error "ELISP:AREF set expects byte 0..255 for unibyte string, got: ~S" value))
    (setf (cl:aref array idx) value))
   ((cl:stringp array)
    (setf (char array idx) (%elisp-code->char value)))
   (t
    (setf (cl:aref array idx) value)))
  value)
