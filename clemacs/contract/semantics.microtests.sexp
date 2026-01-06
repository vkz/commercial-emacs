;; clemacs semantics microtests (living)
;;
;; Purpose:
;; - Capture small, load-order-independent ELisp semantics “breadcrumbs”.
;; - Keep interpreter behavior honest while we bootstrap.
;; - Provide a ready-made corpus to A/B test compiled-vs-interpreted later.
;;
;; Format: a list of plists.
;; Keys:
;; - :name      string (unique, stable identifier)
;; - :expr      string (ELisp expression to eval)
;; - :expected  string (expected prin1 of the result, as clemacs prints it)
;; - :emacs     nil | :match  (when :match, compare clemacs prin1 to system Emacs)
;; - :notes     optional string
;;
;; Policy:
;; - Prefer :emacs :match when we aim for Emacs-faithful semantics.
;; - If clemacs intentionally diverges, set :emacs nil and document the decision
;;   in `plans/clemacs-compat.md` (dated) and keep :expected as the chosen
;;   clemacs behavior.
(
 (:name "strings-stringp"
  :expr "(and (stringp \"abc\") t)"
  :expected "t"
  :emacs :match)

 (:name "strings-string-from-int"
  :expr "(string 97)"
  :expected "\"a\""
  :emacs :match)

 (:name "strings-aref-multibyte-returns-code"
  :expr "(aref \"A\" 0)"
  :expected "65"
  :emacs :match)

 (:name "strings-string-to-unibyte-multibyte-string-p"
  :expr "(multibyte-string-p (string-to-unibyte \"abc\"))"
  :expected "nil"
  :emacs :match)

 (:name "strings-string-to-multibyte-multibyte-string-p"
  :expr "(multibyte-string-p (string-to-multibyte (string-to-unibyte \"abc\")))"
  :expected "t"
  :emacs :match)

 (:name "strings-aref-unibyte-returns-byte"
  :expr "(aref (string-to-unibyte \"A\") 0)"
  :expected "65"
  :emacs :match)

 (:name "text-props-text-property-default-nonsticky-boundp"
  :expr "(boundp 'text-property-default-nonsticky)"
  :expected "t"
  :emacs :match)

 (:name "display-overlay-arrow-variable-list-boundp"
  :expr "(boundp 'overlay-arrow-variable-list)"
  :expected "t"
  :emacs :match)

 (:name "rewrite-let-binding-if-variable"
  :expr "(let ((if 1)) (if (numberp if) if 0))"
  :expected "1"
  :emacs :match)

 (:name "text-props-get-text-property-string-default-nil"
  :expr "(get-text-property 0 'foo \"abc\")"
  :expected "nil"
  :emacs :match)

 (:name "text-props-get-text-property-string-propertize"
  :expr "(let ((s (propertize \"a\" 'foo 1))) (get-text-property 0 'foo s))"
  :expected "1"
  :emacs :match)

 (:name "text-props-put-text-property-buffer-basic"
  :expr "(with-temp-buffer (insert \"abc\") (put-text-property 1 2 'foo 7) (get-text-property 1 'foo))"
  :expected "7"
  :emacs :match)

 (:name "text-props-add-text-properties-buffer-basic"
  :expr "(with-temp-buffer (insert \"abc\") (add-text-properties 2 3 '(foo 1 bar 2)) (list (get-text-property 2 'foo) (get-text-property 2 'bar)))"
  :expected "(1 2)"
  :emacs :match)

 (:name "strings-string-empty-p-empty"
  :expr "(string-empty-p \"\")"
  :expected "t"
  :emacs :match)

 (:name "strings-string-empty-p-nonempty"
  :expr "(string-empty-p \"a\")"
  :expected "nil"
  :emacs :match)

 (:name "prefix-numeric-value-nil"
  :expr "(prefix-numeric-value nil)"
  :expected "1"
  :emacs :match)

 (:name "prefix-numeric-value-t"
  :expr "(prefix-numeric-value t)"
  :expected "1"
  :emacs :match)

 (:name "prefix-numeric-value-cons"
  :expr "(prefix-numeric-value '(16))"
  :expected "16"
  :emacs :match)

 (:name "prefix-numeric-value-dash"
  :expr "(prefix-numeric-value '-)"
  :expected "-1"
  :emacs :match)

 (:name "chars-following-char-eob-is-zero"
  :expr "(with-temp-buffer (insert \"a\") (goto-char (point-max)) (following-char))"
  :expected "0"
  :emacs :match)

 (:name "hash-tables-make-hash-table-weakness-t"
  :expr "(progn (make-hash-table :test 'eq :weakness t) t)"
  :expected "t"
  :emacs :match)

 (:name "chars-preceding-char-bob-is-zero"
  :expr "(with-temp-buffer (insert \"a\") (goto-char (point-min)) (preceding-char))"
  :expected "0"
  :emacs :match)

 (:name "syntax-char-syntax-respects-explicit-table"
  :expr "(with-temp-buffer (let ((st (make-char-table 'syntax-table (cons 0 nil)))) (modify-syntax-entry ?a \"w\" st) (with-syntax-table st (char-syntax ?a))))"
  :expected "119"
  :emacs :match)

 (:name "syntax-tables-modify-syntax-entry-prefix-flag"
  :expr "(let ((st (make-char-table 'syntax-table nil))) (set-char-table-parent st (standard-syntax-table)) (modify-syntax-entry ?\\\" \".   \" st) (modify-syntax-entry ?\\' \"w p\" st) (list (logand (car (aref st ?\\\")) 255) (logand (car (aref st ?\\')) (ash 1 20))))"
  :expected "(1 1048576)"
  :emacs :match)

 (:name "char-script-table-bound-and-char-table"
  :expr "(and (boundp 'char-script-table) (char-table-p char-script-table) t)"
  :expected "t"
  :emacs :match)

 (:name "char-table-set-char-table-range-basic"
  :expr "(let ((ct (make-char-table 'x nil))) (set-char-table-range ct '(1 . 3) 'a) (list (aref ct 1) (aref ct 2) (aref ct 3)))"
  :expected "(a a a)"
  :emacs :match)

 (:name "match-data-basic"
  :expr "(progn (string-match \"b\" \"abc\") (match-beginning 0))"
  :expected "1"
  :emacs :match)

 (:name "match-string-basic"
  :expr "(progn (string-match \"b\" \"abc\") (match-string 0 \"abc\"))"
  :expected "\"b\""
  :emacs :match)

 (:name "regexp-quote-pipe-not-escaped"
  :expr "(regexp-quote \"|\")"
  :expected "\"|\""
  :emacs :match)

 (:name "regexp-quote-plus-escaped"
  :expr "(regexp-quote \"+\")"
  :expected "\"\\\\+\""
  :emacs :match)

 (:name "read-from-string-basic"
  :expr "(car (read-from-string \"(a . b)\"))"
  :expected "(a . b)"
  :emacs :match)

 (:name "reader-bare-colon-symbol"
  :expr "(let* ((x (car (read-from-string \"(: \\\"\\\\\\\\\\\" nonl)\")))) (list (symbol-name (car x)) (aref (cadr x) 0) (symbol-name (nth 2 x))))"
  :expected "(\":\" 92 \"nonl\")"
  :emacs :match)

 (:name "reader-bare-pipe-symbol"
  :expr "(symbol-name (car (car (read-from-string \"(| a b)\"))))"
  :expected "\"|\""
  :emacs :match)

 (:name "prin1-to-string-basic"
  :expr "(prin1-to-string '(a . b))"
  :expected "\"(a . b)\""
  :emacs :match)

 (:name "condition-case-basic"
  :expr "(condition-case e (/ 1 0) (arith-error 'ok))"
  :expected "ok"
  :emacs :match)

 (:name "cl-defmethod-eql-symbol-is-constant"
  :expr "(progn (cl-defgeneric clemacs--cl-defmethod-eql-test (x)) (cl-defmethod clemacs--cl-defmethod-eql-test ((x (eql foo))) 'ok) (clemacs--cl-defmethod-eql-test 'foo))"
  :expected "ok"
  :emacs :match)

 (:name "cl-defmethod-specializer-string"
  :expr "(progn (cl-defgeneric clemacs--cl-defmethod-string-test (x)) (cl-defmethod clemacs--cl-defmethod-string-test ((x string)) 'ok) (clemacs--cl-defmethod-string-test \"hi\"))"
  :expected "ok"
  :emacs :match)

 (:name "save-excursion-point-tracks-insert-before"
  :expr "(with-temp-buffer (insert \"abc\") (goto-char 3) (save-excursion (goto-char 1) (insert \"X\")) (point))"
  :expected "4"
  :emacs :match)

 (:name "forward-char-basic"
  :expr "(with-temp-buffer (insert \"abc\") (goto-char 1) (forward-char 2) (point))"
  :expected "3"
  :emacs :match)

 (:name "forward-char-end-of-buffer-signals-and-clamps"
  :expr "(with-temp-buffer (insert \"abc\") (goto-char 1) (condition-case e (progn (forward-char 10) 'ok) (end-of-buffer (point))))"
  :expected "4"
  :emacs :match)

 (:name "forward-char-beginning-of-buffer-signals-and-clamps"
  :expr "(with-temp-buffer (insert \"abc\") (goto-char 4) (condition-case e (progn (forward-char -10) 'ok) (beginning-of-buffer (point))))"
  :expected "1"
  :emacs :match)

 (:name "backtrace-to-string-basic"
  :expr "(let ((s (backtrace-to-string (backtrace-get-frames nil)))) (and (stringp s) (string-match \"backtrace-get-frames\" s) t))"
  :expected "t"
  :emacs nil
  :notes "Bring-up subset: backtrace frames are (FUN . ARGS) conses, not Emacs backtrace-frame structs.")

 (:name "line-end-position-basic"
  :expr "(with-temp-buffer (insert \"a\\nb\") (goto-char 1) (line-end-position))"
  :expected "2"
  :emacs :match)

 (:name "line-beginning-position-basic"
  :expr "(with-temp-buffer (insert \"a\\nb\") (goto-char 4) (line-beginning-position))"
  :expected "3"
  :emacs :match)

 (:name "beginning-of-line-basic"
  :expr "(with-temp-buffer (insert \"a\\nb\") (goto-char 4) (beginning-of-line) (point))"
  :expected "3"
  :emacs :match)

 (:name "end-of-line-basic"
  :expr "(with-temp-buffer (insert \"a\\nb\") (goto-char 1) (end-of-line) (point))"
  :expected "2"
  :emacs :match)

 (:name "insert-and-inherit-basic"
  :expr "(with-temp-buffer (insert-and-inherit \"a\" \"b\") (buffer-string))"
  :expected "\"ab\""
  :emacs :match)

 (:name "string-width-basic"
  :expr "(string-width \"abc\")"
  :expected "3"
  :emacs :match)

 (:name "window-width-positive"
  :expr "(and (integerp (window-width)) (> (window-width) 0))"
  :expected "t"
  :emacs nil)

 (:name "debugger-special-dynamic-binding"
  :expr "(progn (defun clemacs--debugger-var-probe () debugger) (let ((debugger 'ok)) (clemacs--debugger-var-probe)))"
  :expected "ok"
  :emacs :match)

 (:name "file-names-locate-user-emacs-file-unibyte"
  :expr "(multibyte-string-p (locate-user-emacs-file \"foo\"))"
  :expected "nil"
  :emacs :match)

 (:name "hash-tables-puthash-basic"
  :expr "(let ((h (make-hash-table :test 'eq))) (puthash 'a 1 h) (gethash 'a h))"
  :expected "1"
  :emacs :match)

 (:name "lists-delq-basic"
  :expr "(delq 'a '(a b a c))"
  :expected "(b c)"
  :emacs :match)

 (:name "lists-alist-get-setf-inserts"
  :expr "(let ((a nil)) (setf (alist-get 'x a) 1) a)"
  :expected "((x . 1))"
  :emacs :match)

 (:name "lists-assoc-optional-testfn"
  :expr "(cdr (assoc \"A\" '((\"a\" . 1)) #'string-equal-ignore-case))"
  :expected "1"
  :emacs :match)

 (:name "lists-append-nonlist-tail"
  :expr "(append (list 1) 2)"
  :expected "(1 . 2)"
  :emacs :match)

 (:name "custom-autoload-basic"
  :expr "(progn (custom-autoload 'clemacs--ca \"foo\" t) (symbol-function 'clemacs--ca))"
  :expected "(autoload \"foo\")"
  :emacs nil
  :notes "Bring-up stub used by ldefs-boot/loaddefs: stores an (autoload FILE) marker in the function cell.")

 (:name "function-preserves-local-function-binding"
  :expr "(cl:labels ((rec (x) x)) (cl:mapcar #'rec '(1 2 3)))"
  :expected "(1 2 3)"
  :emacs nil
  :notes "Compiler/codegen breadcrumb: (function SYMBOL) must preserve local function bindings (labels/flet), not just return SYMBOL.")

 (:name "charprop-define-char-code-property-registers"
  :expr "(progn (setq char-code-property-alist nil) (define-char-code-property 'x \"f\" \"d\") (and (assq 'x char-code-property-alist) t))"
  :expected "t"
  :emacs nil)

 (:name "categories-define-category-registers"
  :expr "(progn (setq *defined-categories* (make-hash-table :test 'eql)) (define-category ?a \"ASCII\") (and (equal (gethash ?a *defined-categories*) \"ASCII\") t))"
  :expected "t"
  :emacs nil)

 (:name "cl-type-list-of-accepted"
  :expr "(cl:typep '(a b) '(list-of symbol))"
  :expected "t"
  :emacs nil
  :notes "Compilation aid: accept cl-lib's (list-of TYPE) declarations as a conservative CL type.")

 (:name "cl-deftype-defines-cl-type"
  :expr "(progn (cl-deftype clemacs--tiny nil 'integer) (cl:typep 1 'clemacs--tiny))"
  :expected "t"
  :emacs nil)

 (:name "cl--arglist-args-basic"
  :expr "(equal (cl--arglist-args '(&key a (b nil) &allow-other-keys)) '(a b))"
  :expected "t"
  :emacs nil)

 (:name "narrowing-point-min-max"
  :expr "(with-temp-buffer (insert \"abcdef\") (narrow-to-region 2 5) (list (point-min) (point-max)))"
  :expected "(2 5)"
  :emacs :match)

 (:name "narrowing-goto-char-clamps-to-point-min"
  :expr "(with-temp-buffer (insert \"abcdef\") (narrow-to-region 2 5) (goto-char 1) (point))"
  :expected "2"
  :emacs :match)

 (:name "save-restriction-restores-narrowing"
  :expr "(with-temp-buffer (insert \"abcdef\") (narrow-to-region 2 5) (save-restriction (widen)) (list (point-min) (point-max)))"
  :expected "(2 5)"
  :emacs :match)

 (:name "set-marker-not-clamped-by-narrowing"
  :expr "(with-temp-buffer (insert \"abcdef\") (narrow-to-region 3 5) (let ((m (make-marker))) (set-marker m 1) (marker-position m)))"
  :expected "1"
  :emacs :match)

 (:name "macroexpand-all-env-expander-alist"
  :expr "(progn (defun clemacs--ma-expander (&rest _args) '(quote ok)) (macroexpand-all '(ma-test 1 2) (list (cons 'ma-test 'clemacs--ma-expander))))"
  :expected "'ok"
  :emacs :match)

 (:name "buffer-locals-make-local-variable-basic"
  :expr "(progn (set 'clemacs--microtest-buflocal-var 11) (with-temp-buffer (make-local-variable 'clemacs--microtest-buflocal-var) (setq clemacs--microtest-buflocal-var 22) (list (symbol-value 'clemacs--microtest-buflocal-var) (default-value 'clemacs--microtest-buflocal-var) (local-variable-p 'clemacs--microtest-buflocal-var) (buffer-local-value 'clemacs--microtest-buflocal-var (current-buffer)))))"
  :expected "(22 11 t 22)"
  :emacs :match)

 (:name "buffer-locals-kill-local-variable-restores-default"
  :expr "(progn (set 'clemacs--microtest-buflocal-var2 11) (with-temp-buffer (make-local-variable 'clemacs--microtest-buflocal-var2) (setq clemacs--microtest-buflocal-var2 22) (kill-local-variable 'clemacs--microtest-buflocal-var2) (list (local-variable-p 'clemacs--microtest-buflocal-var2) (symbol-value 'clemacs--microtest-buflocal-var2))))"
  :expected "(nil 11)"
  :emacs :match)

 (:name "buffer-locals-make-variable-buffer-local-makes-setq-local"
  :expr "(progn (set 'clemacs--microtest-buflocal-var3 11) (make-variable-buffer-local 'clemacs--microtest-buflocal-var3) (with-temp-buffer (setq clemacs--microtest-buflocal-var3 33) (list (symbol-value 'clemacs--microtest-buflocal-var3) (default-value 'clemacs--microtest-buflocal-var3) (local-variable-p 'clemacs--microtest-buflocal-var3))))"
  :expected "(33 11 t)"
  :emacs :match)

 (:name "buffer-locals-setq-local-makes-bare-symbol-read-local"
  :expr "(progn (set 'clemacs--microtest-buflocal-var4 11) (with-temp-buffer (make-local-variable 'clemacs--microtest-buflocal-var4) (setq clemacs--microtest-buflocal-var4 22) clemacs--microtest-buflocal-var4))"
  :expected "22"
  :emacs :match)

 (:name "defvar-without-init-leaves-unbound"
  :expr "(progn (makunbound 'clemacs--microtest-defvar-default-nil) (defvar clemacs--microtest-defvar-default-nil) (boundp 'clemacs--microtest-defvar-default-nil))"
  :expected "nil"
  :emacs :match)

 (:name "textprops-buffer-string-preserves-buffer-properties"
  :expr "(with-temp-buffer (insert \"a\") (set-text-properties 1 2 '(foo 7)) (get-text-property 0 'foo (buffer-string)))"
  :expected "7"
  :emacs :match)
)
