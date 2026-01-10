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
;; - Note: :emacs :match comparisons are batched in a single Emacs process per
;;   microtest run; keep exprs load/order independent and avoid relying on
;;   persistent global state across entries.
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

 (:name "reader-char-literal-space"
  :expr "?\\s"
  :expected "32"
  :emacs :match)

 (:name "reader-char-literal-control-del"
  :expr "?\\^?"
  :expected "127"
  :emacs :match)

 (:name "reader-string-literal-control-c-x"
  :expr "(aref \"\\C-x\" 0)"
  :expected "24"
  :emacs :match)

 (:name "reader-symbol-question-mark-constituent"
  :expr "(symbol-name 'first?)"
  :expected "\"first?\""
  :emacs :match)

 (:name "pcase-pred-fun-form-appends-expval"
  :expr "(pcase \"abc\" ((pred (string-match \"a\")) t) (_ nil))"
  :expected "t"
  :emacs :match)

 (:name "reader-struct-literal-prints-as-#s"
  :expr "(prin1-to-string #s(e (f [g])))"
  :expected "\"#s(e (f [g]))\""
  :emacs :match)

 (:name "text-props-text-property-default-nonsticky-boundp"
  :expr "(boundp 'text-property-default-nonsticky)"
  :expected "t"
  :emacs :match)

 (:name "display-overlay-arrow-variable-list-boundp"
  :expr "(boundp 'overlay-arrow-variable-list)"
  :expected "t"
  :emacs :match)

 (:name "display-standard-display-table-boundp"
  :expr "(boundp 'standard-display-table)"
  :expected "t"
  :emacs :match)

 (:name "faces-face-id-core"
  :expr "(mapcar (lambda (s) (face-id s)) '(default bold italic bold-italic underline fixed-pitch fixed-pitch-serif variable-pitch variable-pitch-text))"
  :expected "(0 1 2 3 4 5 6 7 8)"
  :emacs :match)

 (:name "faces-face-list-includes-core"
  :expr "(and (memq 'default (face-list)) (memq 'underline (face-list)) t)"
  :expected "t"
  :emacs :match)

 (:name "files-interpreter-mode-alist-boundp"
  :expr "(boundp 'interpreter-mode-alist)"
  :expected "t"
  :emacs :match)

 (:name "rx-bos-any-unibyte"
  :expr "(rx bos (any \"/:\"))"
  :expected "\"\\\\`[/:]\""
  :emacs :match)

 (:name "rx-not-any-unibyte"
  :expr "(rx (not (any \"/:\")))"
  :expected "\"[^/:]\""
  :emacs :match)

 (:name "rx-ge-not-any"
  :expr "(rx (>= 2 (not (any \"/:|\"))))"
  :expected "\"[^/:|]\\\\{2,\\\\}\""
  :emacs :match)

 (:name "charset-define-char-code-property-accepts-two-args"
  :expr "(progn (define-char-code-property 'clemacs--tmp-char-code-prop \"x.el\") t)"
  :expected "t"
  :emacs nil)

 (:name "mule-register-input-method-updates-input-method-alist"
  :expr "(progn (setq input-method-alist nil) (register-input-method 'foo 'bar 'quail-use-package \"T\" \"D\" 'x) (register-input-method \"foo\" \"bar\" 'quail-use-package \"T2\" \"D2\") input-method-alist)"
  :expected "((\"foo\" \"bar\" quail-use-package \"T2\" \"D2\"))"
  :emacs :match)

 (:name "macros-eval-when-compile-evaluates-body"
  :expr "(progn (setq clemacs--tmp-ewc 0) (eval-when-compile (setq clemacs--tmp-ewc 1)) clemacs--tmp-ewc)"
  :expected "1"
  :emacs :match)

 (:name "macros-let-when-compile-binds-for-eval-when-compile"
  :expr "(progn (setq clemacs--tmp-lwc 0) (let-when-compile ((x 7)) (eval-when-compile (setq clemacs--tmp-lwc x))) clemacs--tmp-lwc)"
  :expected "7"
  :emacs :match)

 (:name "function-lambda-funcall"
  :expr "(funcall (function (lambda (x) (1+ x))) 1)"
  :expected "2"
  :emacs :match)

 (:name "function-compiled-function-p-lambda-nil"
  :expr "(compiled-function-p (lambda (x) x))"
  :expected "nil"
  :emacs :match)

 (:name "rewrite-let-binding-if-variable"
  :expr "(let ((if 1)) (if (numberp if) if 0))"
  :expected "1"
  :emacs :match)

 (:name "lists-member-uses-equal"
  :expr "(let ((x (cons 'a 'b))) (member (cons 'a 'b) (list x)))"
  :expected "((a . b))"
  :emacs :match)

 (:name "keymaps-ctl-x-r-map-bound-and-keymapp"
  :expr "(and (boundp 'ctl-x-r-map) (keymapp ctl-x-r-map))"
  :expected "t"
  :emacs :match)

 (:name "keymaps-keymapp-symbol-function-cell-keymap"
  :expr "(let ((s (make-symbol \"clemacs--tmp-prefix\")) (m (make-sparse-keymap))) (fset s m) (keymapp s))"
  :expected "t"
  :emacs :match)

 (:name "keymaps-key-parse-c-x-c-s"
  :expr "(key-parse \"C-x C-s\")"
  :expected "[24 19]"
  :emacs :match)

 (:name "keymaps-key-parse-m-p-esc-prefix"
  :expr "(key-parse \"M-p\")"
  :expected "[27 112]"
  :emacs nil
  :notes "clemacs TTY currently represents Meta as an ESC prefix (esc-map).")

 (:name "keymaps-bindings--define-key-defines-key"
  :expr "(let ((m (make-sparse-keymap))) (bindings--define-key m [load] 'foo) (eq (lookup-key m [load]) 'foo))"
  :expected "t"
  :emacs :match)

 (:name "read-string-parses-vector"
  :expr "(equal (read \"[1 2]\") [1 2])"
  :expected "t"
  :emacs :match)

 (:name "cl-progv-binds-dynamically"
  :expr "(progn (require 'cl-lib) (cl-progv '(x) '(7) x))"
  :expected "7"
  :emacs :match)

 (:name "cl-generic-cl-defgeneric-supports-optional-args"
  :expr "(progn (require 'cl-lib) (cl-defgeneric clemacs--g (a &optional b) (or b a)) (clemacs--g 1))"
  :expected "1"
  :emacs :match)

 (:name "strings-string-to-char-empty-is-zero"
  :expr "(string-to-char \"\")"
  :expected "0"
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

 (:name "text-props-text-property-any-string-basic"
  :expr "(let ((s (propertize \"ab\" 'foo 1))) (text-property-any 0 2 'foo 1 s))"
  :expected "0"
  :emacs :match)

 (:name "text-props-next-prev-single-property-change-string-basic"
  :expr "(let ((s (propertize \"ab\" 'foo 1))) (put-text-property 1 2 'foo 2 s) (list (next-single-property-change 0 'foo s) (next-single-property-change 1 'foo s) (previous-single-property-change 2 'foo s)))"
  :expected "(1 nil 1)"
  :emacs :match)

 (:name "text-props-next-prev-single-property-change-string-limits"
  :expr "(let ((s (propertize \"ab\" 'foo 1))) (put-text-property 1 2 'foo 2 s) (list (next-single-property-change 2 'foo s 1) (next-single-property-change 1 'foo s 0) (previous-single-property-change 0 'foo s 1) (previous-single-property-change 1 'foo s 2)))"
  :expected "(1 0 1 2)"
  :emacs :match)

 (:name "text-props-next-prev-property-change-string"
  :expr "(let ((s (propertize \"ab\" 'foo 1))) (put-text-property 1 2 'foo 2 s) (list (next-property-change 0 s) (next-property-change 1 s) (next-property-change 1 s 2) (next-property-change 2 s 1) (previous-property-change 2 s) (previous-property-change 1 s 0) (previous-property-change 0 s 1)))"
  :expected "(1 nil 2 1 1 0 1)"
  :emacs :match)

 (:name "text-props-next-prev-property-change-buffer"
  :expr "(with-temp-buffer (insert \"ab\") (put-text-property 1 2 'foo 1) (put-text-property 2 3 'foo 2) (list (next-property-change 1 nil) (next-property-change 2 nil) (next-property-change 2 nil 3) (next-property-change 3 nil 1) (previous-property-change 3 nil) (previous-property-change 2 nil) (previous-property-change 2 nil 1) (previous-property-change 1 nil 3)))"
  :expected "(2 nil 3 1 2 nil 1 3)"
  :emacs :match)

 (:name "files-file-attributes-size-make-temp-file"
  :expr "(let ((f (make-temp-file \"clemacs-microtest-\" nil nil \"abc\"))) (nth 7 (file-attributes f 'integer)))"
  :expected "3"
  :emacs :match)

 (:name "files-insert-file-contents-basic"
  :expr "(let ((f (make-temp-file \"clemacs-ifc-\" nil nil \"hi\"))) (with-temp-buffer (let ((ret (insert-file-contents f))) (and (equal (buffer-string) \"hi\") (= (cadr ret) 2) t))))"
  :expected "t"
  :emacs :match)

 (:name "files-write-region-utf8-roundtrip"
  :expr "(let* ((f (make-temp-file \"clemacs-wr-\")) (s \"héllo ☃\\n\")) (write-region s nil f nil 'quiet) (with-temp-buffer (insert-file-contents f) (string= (buffer-string) s)))"
  :expected "t"
  :emacs :match)

 (:name "strings-string-empty-p-empty"
  :expr "(string-empty-p \"\")"
  :expected "t"
  :emacs :match)

 (:name "strings-string-empty-p-nonempty"
  :expr "(string-empty-p \"a\")"
  :expected "nil"
  :emacs :match)

 (:name "strings-string-trim-family-basic"
  :expr "(list (string-trim \" foo \") (string-trim-left \"oofoo\" \"o+\") (string-trim-right \"barkss\" \"s+\"))"
  :expected "(\"foo\" \"foo\" \"bark\")"
  :emacs :match)

 (:name "strings-number-to-string-floats"
  :expr "(list (number-to-string 42) (number-to-string 1.0) (number-to-string 1.5) (number-to-string 1000000.0) (number-to-string 1e-6) (number-to-string 1e-4) (number-to-string 1e15))"
  :expected "(\"42\" \"1.0\" \"1.5\" \"1000000.0\" \"1e-06\" \"0.0001\" \"1e+15\")"
  :emacs :match)

 (:name "strings-string-replace-basic"
  :expr "(string-replace \"%%\" \"%\" \"a%%b%%\")"
  :expected "\"a%b%\""
  :emacs :match)

 (:name "strings-replace-regexp-in-string-basic"
  :expr "(list (replace-regexp-in-string \"[ \\t]*\\\\'\" \"\" \"a \\t\") (replace-regexp-in-string \"foo\" \"bar\" \" foo foo\"))"
  :expected "(\"a\" \" bar bar\")"
  :emacs :match)

 (:name "strings-string-collate-lessp-basic"
  :expr "(list (string-collate-lessp \"a\" \"b\") (string-collate-lessp \"b\" \"a\") (string-collate-lessp \"A\" \"a\" nil t) (string-collate-lessp \"a\" \"A\" nil t))"
  :expected "(t nil t nil)"
  :emacs :match)

 (:name "files-file-name-absolute-p-basic"
  :expr "(list (file-name-absolute-p \"/a\") (file-name-absolute-p \"a\") (file-name-absolute-p \"~/a\"))"
  :expected "(t nil t)"
  :emacs :match)

 (:name "files-file-name-directory-basic"
  :expr "(list (file-name-directory \"foo\") (file-name-directory \"foo/bar\") (file-name-directory \"/foo\") (file-name-directory \"/foo/\") (file-name-directory \"~/a\"))"
  :expected "(nil \"foo/\" \"/\" \"/foo/\" \"~/\")"
  :emacs :match)

 (:name "files-file-name-extension-basic"
  :expr "(list (file-name-extension \"foo.tar.gz\") (file-name-extension \"foo.tar.gz\" t) (file-name-extension \"foo.\") (file-name-extension \"foo.\" t) (file-name-extension \"/a/b.c~\") (file-name-extension \"/a/b.c~\" t))"
  :expected "(\"gz\" \".gz\" \"\" \".\" \"c\" \".c\")"
  :emacs :match)

 (:name "files-file-truename-dot-absolute-and-noslash"
  :expr "(let* ((s (file-truename \".\")) (n (length s))) (and (file-name-absolute-p s) (not (and (> n 1) (= (aref s (1- n)) ?/)))))"
  :expected "t"
  :emacs :match)

 (:name "coding-coding-system-p-basic"
  :expr "(list (coding-system-p 'utf-8) (coding-system-p nil) (coding-system-p t))"
  :expected "(t t nil)"
  :emacs :match)

 (:name "coding-unibyte-char-to-multibyte-basic"
  :expr "(list (unibyte-char-to-multibyte 161) (unibyte-char-to-multibyte 65) (unibyte-char-to-multibyte 128) (unibyte-char-to-multibyte 255))"
  :expected "(4194209 65 4194176 4194303)"
  :emacs :match)

 (:name "coding-max-char-basic"
  :expr "(list (max-char 'unicode) (max-char 'ascii) (max-char))"
  :expected "(1114111 1114111 4194303)"
  :emacs :match)

 (:name "display-display-graphic-p-nil"
  :expr "(display-graphic-p)"
  :expected "nil"
  :emacs :match)

 (:name "strings-compare-strings-basic"
  :expr "(list (compare-strings \"abc\" 0 nil \"abc\" 0 nil nil) (compare-strings \"abc\" 0 nil \"abd\" 0 nil nil) (compare-strings \"abd\" 0 nil \"abc\" 0 nil nil) (compare-strings \"ab\" 0 nil \"abc\" 0 nil nil) (compare-strings \"abc\" 0 nil \"ab\" 0 nil nil) (compare-strings \"Ab\" 0 nil \"aB\" 0 nil t))"
  :expected "(t -3 3 -3 3 t)"
  :emacs :match)

 (:name "strings-compare-strings-nil-and-negative-indices"
  :expr "(list (compare-strings \"abc\" 1 3 \"xbc\" 1 3 nil) (compare-strings \"abc\" -2 nil \"xbc\" -2 nil nil) (compare-strings \"abc\" nil nil \"xbc\" nil nil nil) (compare-strings \"abc\" nil nil \"abcd\" nil nil nil) (compare-strings \"abcd\" nil nil \"abc\" nil nil nil))"
  :expected "(t t -1 -4 4)"
  :emacs :match)

 (:name "strings-file-size-human-readable-basic"
  :expr "(list (file-size-human-readable 999) (file-size-human-readable 1024) (file-size-human-readable 1536) (file-size-human-readable 1048576))"
  :expected "(\"999\" \"1k\" \"1.5k\" \"1M\")"
  :emacs :match)

 (:name "coding-unencodable-char-position-us-ascii"
  :expr "(let ((s \"aΩb\")) (list (unencodable-char-position 0 (length s) 'us-ascii nil s) (unencodable-char-position 0 (length s) 'us-ascii 11 s)))"
  :expected "(1 (1))"
  :emacs :match)

 (:name "keymaps-copy-keymap-parent-basic"
  :expr "(let* ((p (make-sparse-keymap)) (m (make-sparse-keymap)) (_ (set-keymap-parent m p)) (c (copy-keymap m))) (list (keymapp c) (eq (keymap-parent c) p) (eq c m)))"
  :expected "(t t nil)"
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

 (:name "symbol-name-keyword"
  :expr "(symbol-name :foo)"
  :expected "\":foo\""
  :emacs :match)

 (:name "reader-#s-hash-table"
  :expr "(let* ((ht (car (read-from-string \"#s(hash-table test eq data (a 1 b 2))\")))) (list (hash-table-test ht) (gethash 'a ht) (gethash 'b ht)))"
  :expected "(eq 1 2)"
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

 (:name "buffer-file-name-temp-buffer-nil"
  :expr "(with-temp-buffer (buffer-file-name))"
  :expected "nil"
  :emacs :match)

 (:name "directory-file-name-trims-trailing-slash"
  :expr "(directory-file-name \"/tmp/\")"
  :expected "\"/tmp\""
  :emacs :match)

 (:name "move-to-column-basic"
  :expr "(with-temp-buffer (insert \"abcd\") (goto-char 1) (move-to-column 2) (point))"
  :expected "3"
  :emacs :match)

 (:name "frame-parameter-window-system-nil"
  :expr "(frame-parameter nil 'window-system)"
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

 (:name "advertised-calling-convention-autoload-marker"
  :expr "(progn (autoload 'clemacs--acc \"cl-print\") (get-advertised-calling-convention (symbol-function 'clemacs--acc)))"
  :expected "t"
  :emacs :match
  :notes "Emacs returns `t` when queried on an autoload placeholder; cl-generic calls this during method definition/defalias.")

 (:name "interactive-form-commandp-defun"
  :expr "(progn (defun clemacs--it0 () (interactive) 1) (list (interactive-form 'clemacs--it0) (commandp 'clemacs--it0)))"
  :expected "((interactive nil) t)"
  :emacs :match)

 (:name "call-interactively-prefix-p"
  :expr "(progn (defun clemacs--itp (x) (interactive \"p\") x) (let ((current-prefix-arg 5)) (call-interactively 'clemacs--itp)))"
  :expected "5"
  :emacs :match)

 (:name "read-event-honors-unread-command-events"
  :expr "(progn (setq unread-command-events '(65)) (list (read-event) unread-command-events))"
  :expected "(65 nil)"
  :emacs nil
  :notes "clemacs TTY loop uses `unread-command-events` for pushback (universal-argument and friends).")

 (:name "universal-argument-sets-prefix-arg-and-pushes-back"
  :expr "(progn (setq unread-command-events '(6)) (setq prefix-arg nil) (setq current-prefix-arg nil) (universal-argument) (list prefix-arg unread-command-events))"
  :expected "((4) (6))"
  :emacs nil)

 (:name "universal-argument-digit-prefix"
  :expr "(progn (setq unread-command-events '(51 6)) (setq prefix-arg nil) (setq current-prefix-arg nil) (universal-argument) (list prefix-arg unread-command-events))"
  :expected "(3 (6))"
  :emacs nil)

 (:name "read-from-minibuffer-noninteractive-uses-default"
  :expr "(progn (setq noninteractive t) (read-from-minibuffer \"P: \" nil nil nil nil \"D\" nil))"
  :expected "\"D\""
  :emacs nil)

 (:name "add-to-history-prepend-and-dedup"
  :expr "(progn (setq history-delete-duplicates t) (setq clemacs--hist nil) (add-to-history 'clemacs--hist \"a\") (add-to-history 'clemacs--hist \"b\") (add-to-history 'clemacs--hist \"a\") clemacs--hist)"
  :expected "(\"a\" \"b\")"
  :emacs :match)

 (:name "read-from-minibuffer-noninteractive-adds-history"
  :expr "(progn (setq noninteractive t) (setq clemacs--mh nil) (read-from-minibuffer \"P: \" nil nil nil 'clemacs--mh \"D\" nil) clemacs--mh)"
  :expected "(\"D\")"
  :emacs nil)

 (:name "execute-kbd-macro-basic"
  :expr "(progn (setq noninteractive t) (defun clemacs--kmtest () (interactive) (insert \"Z\")) (use-global-map (make-sparse-keymap)) (define-key (current-global-map) \"a\" 'clemacs--kmtest) (with-temp-buffer (execute-kbd-macro \"a\") (buffer-string)))"
  :expected "\"Z\""
  :emacs nil)

 (:name "minibuffer-prompt-safe-self-insert"
  :expr "(with-temp-buffer (insert \"P> \") (setq *clemacs-minibuffer-prompt-end* (point)) (goto-char 1) (setq last-command-event 97) (clemacs-minibuffer-self-insert-command 1) (buffer-string))"
  :expected "\"P> a\""
  :emacs nil)

 (:name "minibuffer-prompt-safe-backspace"
  :expr "(with-temp-buffer (insert \"P> \") (setq *clemacs-minibuffer-prompt-end* (point)) (insert \"a\") (goto-char *clemacs-minibuffer-prompt-end*) (clemacs-minibuffer-delete-backward-char 1) (buffer-string))"
  :expected "\"P> a\""
  :emacs nil)

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
  :expr "(progn (defvar clemacs--microtest-buflocal-var4) (set 'clemacs--microtest-buflocal-var4 11) (with-temp-buffer (make-local-variable 'clemacs--microtest-buflocal-var4) (setq clemacs--microtest-buflocal-var4 22) clemacs--microtest-buflocal-var4))"
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

 (:name "textprops-remove-list-of-text-properties-clears"
  :expr "(with-temp-buffer (insert \"ab\") (set-text-properties 1 3 '(foo 7)) (remove-list-of-text-properties 1 3 '(foo)) (get-text-property 0 'foo (buffer-string)))"
  :expected "nil"
  :emacs :match)

 (:name "files-file-name-base-basic"
  :expr "(file-name-base \"a/b/c.txt\")"
  :expected "\"c\""
  :emacs :match)

 (:name "prints-with-output-to-string-princ"
  :expr "(with-output-to-string (princ \"hi\"))"
  :expected "\"hi\""
  :emacs :match)

 (:name "macros-thread-last-basic"
  :expr "(progn (require 'subr-x) (thread-last 1 (+ 2) (* 3)))"
  :expected "9"
  :emacs :match)

 (:name "pcase-constant-integer-pattern"
  :expr "(pcase 0 (0 'yes) (_ 'no))"
  :expected "yes"
  :emacs :match)

 (:name "pcase-symbol-binding-and-pred"
  :expr "(pcase \"x\" ((and v (pred stringp)) v) (_ nil))"
  :expected "\"x\""
  :emacs :match)

 (:name "pcase-and-guard"
  :expr "(pcase 3 ((and x (guard (> x 2))) x) (_ nil))"
  :expected "3"
  :emacs :match)

 (:name "pcase-let-expr-guard"
  :expr "(let ((mandatory 'context)) (pcase 'foo ((let 'context mandatory) 'yes) (_ 'no)))"
  :expected "yes"
  :emacs :match)

 (:name "pcase-let-binds-from-and"
  :expr "(pcase 'foo ((and (pred symbolp) var (let exp var)) (list var exp)) (_ nil))"
  :expected "(foo foo)"
  :emacs :match)

 (:name "pcase-bq-unquote-subpattern-pred"
  :expr "(pcase '(a . b) (`(a . ,(pred symbolp)) 'yes) (_ 'no))"
  :expected "yes"
  :emacs :match)

 (:name "pcase-bq-unquote-subpattern-or"
  :expr "(pcase '(1 2) (`(1 ,(or 2 3)) 'yes) (_ 'no))"
  :expected "yes"
  :emacs :match)

 (:name "regexp-match-data-translate-shifts"
  :expr "(progn (string-match \"a\" \"za\") (match-data--translate -1) (match-beginning 0))"
  :expected "0"
  :emacs :match)

 (:name "buffers-save-current-buffer-does-not-capture-buf"
  :expr "(let ((buf 123)) (save-current-buffer buf))"
  :expected "123"
  :emacs :match)

 (:name "seq-mapconcat-basic-list"
  :expr "(mapconcat #'identity '(\"a\" \"b\" \"c\") \"_\")"
  :expected "\"a_b_c\""
  :emacs :match)

 (:name "seq-mapconcat-basic-string"
  :expr "(mapconcat #'char-to-string \"abc\" \"-\")"
  :expected "\"a-b-c\""
  :emacs :match)

 (:name "seq-seq-filter-basic-list"
  :expr "(seq-filter #'numberp '(a 1 b 2))"
  :expected "(1 2)"
  :emacs :match)

 (:name "seq-seq-filter-basic-string"
  :expr "(seq-filter (lambda (c) (or (= c ?b) (= c ?c))) \"abcd\")"
  :expected "(98 99)"
  :emacs :match)

 (:name "buffers-buffer-modified-p-insert"
  :expr "(with-temp-buffer (insert \"a\") (buffer-modified-p))"
  :expected "t"
  :emacs :match)

 (:name "buffers-set-buffer-modified-p-clears"
  :expr "(with-temp-buffer (insert \"a\") (set-buffer-modified-p nil) (buffer-modified-p))"
  :expected "nil"
  :emacs :match)

 (:name "windows-single-window-basics"
  :expr "(let ((w (selected-window))) (and (window-live-p w) (eq w (select-window w)) (eq (current-buffer) (window-buffer w)) t))"
  :expected "t"
  :emacs :match)

 (:name "windows-windowp-selected"
  :expr "(windowp (selected-window))"
  :expected "t"
  :emacs :match)

 (:name "windows-get-buffer-window-current"
  :expr "(eq (get-buffer-window (current-buffer)) (selected-window))"
  :expected "t"
  :emacs :match)

 (:name "windows-save-selected-window-noop"
  :expr "(let ((w (selected-window))) (save-selected-window (select-window w) (eq (selected-window) w)))"
  :expected "t"
  :emacs :match)

 (:name "windows-with-selected-window-noop"
  :expr "(let ((w (selected-window))) (with-selected-window w (eq (selected-window) w)))"
  :expected "t"
  :emacs :match)

 (:name "buffers-search-forward-basic"
  :expr "(with-temp-buffer (insert \"abc abc\") (goto-char 1) (list (search-forward \"abc\") (point) (search-forward \"abc\" nil t) (point) (match-beginning 0) (match-end 0)))"
  :expected "(4 4 8 8 5 8)"
  :emacs :match)

 (:name "buffers-insert-buffer-substring-basic"
  :expr "(let ((a (get-buffer-create \"*A*\") ) (b (get-buffer-create \"*B*\"))) (with-current-buffer a (erase-buffer) (insert \"abc\")) (with-current-buffer b (erase-buffer) (insert \"x\") (insert-buffer-substring a 2 4) (buffer-string)))"
  :expected "\"xbc\""
  :emacs :match)

 (:name "buffers-line-number-at-pos-basic"
  :expr "(with-temp-buffer (insert \"a\\nb\\nc\") (list (line-number-at-pos 1) (line-number-at-pos 3) (line-number-at-pos 5)))"
  :expected "(1 2 3)"
  :emacs :match)

 (:name "buffers-mark-basic"
  :expr "(with-temp-buffer (insert \"abc\") (goto-char 2) (push-mark 3 t t) (mark t))"
  :expected "3"
  :emacs :match)

 (:name "messages-minibuffer-message-returns-t"
  :expr "(minibuffer-message \"hi\")"
  :expected "t"
  :emacs :match)

 (:name "overlays-move-overlay-updates-start-end"
  :expr "(with-temp-buffer (insert \"abcd\") (let ((ov (make-overlay 2 4))) (move-overlay ov 1 3) (list (overlay-start ov) (overlay-end ov))))"
  :expected "(1 3)"
  :emacs :match)

 (:name "text-get-char-property-overlay-wins"
  :expr "(with-temp-buffer (insert \"abc\") (let ((ov (make-overlay 1 2))) (overlay-put ov 'foo 7) (get-char-property 1 'foo)))"
  :expected "7"
  :emacs :match)

 (:name "buffers-bury-buffer-returns-nil"
  :expr "(let ((b (get-buffer-create \"*BB*\"))) (switch-to-buffer b) (bury-buffer b))"
  :expected "nil"
  :emacs :match)

 (:name "hooks-run-hook-wrapped-stops-on-non-nil"
  :expr "(let ((h 'clemacs-test-hook) (x 0)) (set h (list (lambda () (setq x 1) nil) (lambda () (setq x 2) 'stop) (lambda () (setq x 3) nil))) (list (run-hook-wrapped h (lambda (f) (funcall f))) x))"
  :expected "(stop 2)"
  :emacs :match)

 (:name "input-input-pending-p-nil"
  :expr "(input-pending-p)"
  :expected "nil"
  :emacs :match)

 (:name "input-discard-input-nil"
  :expr "(discard-input)"
  :expected "nil"
  :emacs :match)

 (:name "byte-compile-warn-returns-nil"
  :expr "(byte-compile-warn \"x\")"
  :expected "nil"
  :emacs nil)

 (:name "frames-frame-list-length-1"
  :expr "(= (length (frame-list)) 1)"
  :expected "t"
  :emacs :match)

 (:name "frames-frame-char-width-positive"
  :expr "(and (integerp (frame-char-width)) (> (frame-char-width) 0))"
  :expected "t"
  :emacs :match)

 (:name "syntax-parse-partial-sexp-depth-zero"
  :expr "(with-temp-buffer (insert \"(a (b))\") (car (parse-partial-sexp 1 (point-max))))"
  :expected "0"
  :emacs :match)

 (:name "syntax-ppss-in-string-nth3-and-start"
  :expr "(with-temp-buffer (emacs-lisp-mode) (insert \"\\\"ab\\\"\") (goto-char 3) (let ((st (syntax-ppss))) (list (nth 3 st) (nth 8 st) (point))) )"
  :expected "(34 1 3)"
  :emacs :match)

 (:name "syntax-ppss-in-comment-nth4-and-start"
  :expr "(with-temp-buffer (emacs-lisp-mode) (insert \"a;xx\\n\") (goto-char 3) (let ((st (syntax-ppss))) (list (nth 4 st) (nth 8 st) (point))) )"
  :expected "(t 2 3)"
  :emacs :match)

 (:name "syntax-parse-partial-sexp-commentstop-stops-at-comment"
  :expr "(with-temp-buffer (emacs-lisp-mode) (insert \"a;xx\\n\") (goto-char 1) (let ((st (parse-partial-sexp 1 (point-max) nil nil nil t))) (list (point) (nth 4 st) (nth 8 st))) )"
  :expected "(3 t 2)"
  :emacs :match)

 (:name "vars-special-variable-p-defvar"
  :expr "(progn (defvar clemacs-svp 1) (special-variable-p 'clemacs-svp))"
  :expected "t"
  :emacs :match)

 (:name "files-file-relative-name-basic"
  :expr "(file-relative-name \"/tmp/a\" \"/tmp/\")"
  :expected "\"a\""
  :emacs :match)

 (:name "coding-encode-coding-string-identity"
  :expr "(encode-coding-string \"abc\" 'raw-text)"
  :expected "\"abc\""
  :emacs :match)

 (:name "buffers-forward-word-basic"
  :expr "(with-temp-buffer (insert \"aa bb\") (goto-char 1) (forward-word 1) (point))"
  :expected "3"
  :emacs :match)

 (:name "buffers-vertical-motion-zero-goes-to-bol"
  :expr "(with-temp-buffer (insert \"ab\\ncd\") (goto-char 2) (vertical-motion 0) (point))"
  :expected "1"
  :emacs :match)

 (:name "commands-command-remapping-nil"
  :expr "(command-remapping 'foo)"
  :expected "nil"
  :emacs :match)

 (:name "buffers-kill-all-local-variables-clears-local"
  :expr "(with-temp-buffer (setq clemacs-klv 1) (make-local-variable 'clemacs-klv) (setq clemacs-klv 2) (kill-all-local-variables) (local-variable-p 'clemacs-klv))"
  :expected "nil"
  :emacs :match)

 (:name "windows-minibuffer-selected-window-nil"
  :expr "(minibuffer-selected-window)"
  :expected "nil"
  :emacs :match)

 (:name "windows-window-minibuffer-p-nil"
  :expr "(window-minibuffer-p (selected-window))"
  :expected "nil"
  :emacs :match)

 (:name "windows-active-minibuffer-window-nil"
  :expr "(active-minibuffer-window)"
  :expected "nil"
  :emacs :match)

 (:name "windows-window-minibuffer-p-minibuffer-window-t"
  :expr "(window-minibuffer-p (minibuffer-window))"
  :expected "t"
  :emacs :match)

 (:name "windows-minibufferp-nil"
  :expr "(minibufferp)"
  :expected "nil"
  :emacs :match)

 (:name "windows-minibufferp-minibuf-0-t"
  :expr "(minibufferp (get-buffer-create \" *Minibuf-0*\"))"
  :expected "t"
  :emacs :match)

 (:name "minibuffer-depth-top-level-zero"
  :expr "(= (minibuffer-depth) 0)"
  :expected "t"
  :emacs :match)

 (:name "completing-read-noninteractive-default"
  :expr "(let ((old noninteractive)) (unwind-protect (progn (setq noninteractive t) (completing-read \"P: \" '(\"a\" \"b\") nil t nil nil \"b\")) (setq noninteractive old)))"
  :expected "\"b\""
  :emacs nil)

 (:name "windows-window-height-positive"
  :expr "(and (integerp (window-height)) (> (window-height) 0))"
  :expected "t"
  :emacs :match)

 (:name "windows-window-point-follows-point"
  :expr "(save-window-excursion (let ((b (get-buffer-create \"*WPT*\"))) (with-current-buffer b (erase-buffer) (insert \"abc\") (goto-char 2)) (switch-to-buffer b) (= (window-point (selected-window)) 2)))"
  :expected "t"
  :emacs :match)

 (:name "keymaps-lookup-key-single-char"
  :expr "(let ((m (make-sparse-keymap))) (define-key m \"a\" 'foo) (eq (lookup-key m \"a\") 'foo))"
  :expected "t"
  :emacs :match)

 (:name "keymaps-lookup-key-vector-sequence"
  :expr "(let ((m (make-sparse-keymap))) (define-key m [24 97] 'bar) (eq (lookup-key m [24 97]) 'bar))"
  :expected "t"
  :emacs :match)

 (:name "keymaps-map-keymap-collect-keys"
  :expr "(let ((m (make-sparse-keymap)) (ks nil)) (define-key m \"a\" 'foo) (define-key m \"b\" 'bar) (map-keymap (lambda (k _v) (push k ks)) m) (and (= (length ks) 2) (memq ?a ks) (memq ?b ks) t))"
  :expected "t"
  :emacs :match)

 (:name "overlays-basic-start-end"
  :expr "(with-temp-buffer (insert \"abc\") (let ((ov (make-overlay 1 3))) (and (= (overlay-start ov) 1) (= (overlay-end ov) 3) (bufferp (overlay-buffer ov)) t)))"
  :expected "t"
  :emacs :match)

 (:name "overlays-put-get"
  :expr "(with-temp-buffer (insert \"abc\") (let ((ov (make-overlay 1 2))) (overlay-put ov 'foo 7) (equal (overlay-get ov 'foo) 7)))"
  :expected "t"
  :emacs :match)

 (:name "overlays-delete-clears-buffer-and-start"
  :expr "(with-temp-buffer (insert \"abc\") (let ((ov (make-overlay 1 2))) (delete-overlay ov) (and (null (overlay-buffer ov)) (null (overlay-start ov)))))"
  :expected "t"
  :emacs :match)

 (:name "mapconcat-default-separator-nil"
  :expr "(mapconcat #'identity '(\"a\" \"b\"))"
  :expected "\"ab\""
  :emacs :match)

 (:name "regexp-quote-rbracket"
  :expr "(regexp-quote \"]\")"
  :expected "\"]\""
  :emacs :match)

 (:name "pcase-keyword-constant"
  :expr "(pcase 'x (:foo 'bad) (_ 'ok))"
  :expected "ok"
  :emacs :match)

 (:name "core-nlistp"
  :expr "(list (nlistp nil) (nlistp '(1)) (nlistp 3))"
  :expected "(nil nil t)"
  :emacs :match)

 (:name "symbols-put-preserves-plist-order"
  :expr "(let ((x (make-symbol \"x\"))) (put x 'a 1) (put x 'b 2) (put x 'c 3) (symbol-plist x))"
  :expected "(a 1 b 2 c 3)"
  :emacs :match)

 (:name "call-interactively-p-prefix-numeric"
  :expr "(progn (defun clemacs-test--ci-p (n) (interactive \"p\") n) (setq current-prefix-arg 7) (call-interactively 'clemacs-test--ci-p))"
  :expected "7"
  :emacs :match)

 (:name "call-interactively-P-raw-prefix"
  :expr "(progn (defun clemacs-test--ci-P (x) (interactive \"P\") x) (setq current-prefix-arg '(4)) (call-interactively 'clemacs-test--ci-P))"
  :expected "(4)"
  :emacs :match)

 (:name "barf-if-buffer-read-only-signals"
  :expr "(with-temp-buffer (setq buffer-read-only t) (condition-case _e (progn (barf-if-buffer-read-only) 'bad) (buffer-read-only 'ok)))"
  :expected "ok"
  :emacs :match)

 (:name "syntax-ppss-empty"
  :expr "(with-temp-buffer (emacs-lisp-mode) (syntax-ppss))"
  :expected "(0 nil nil nil nil nil 0 nil nil nil nil)"
  :emacs :match)

 (:name "syntax-ppss-in-comment"
  :expr "(with-temp-buffer (emacs-lisp-mode) (insert \"(foo ; c\\n \\\"str\\\" (bar))\") (goto-char 8) (list (nth 0 (syntax-ppss)) (nth 4 (syntax-ppss)) (nth 8 (syntax-ppss)) (nth 9 (syntax-ppss))))"
  :expected "(1 t 6 (1))"
  :emacs :match)

 (:name "syntax-ppss-in-string"
  :expr "(with-temp-buffer (emacs-lisp-mode) (insert \"(foo ; c\\n \\\"str\\\" (bar))\") (goto-char 14) (list (nth 0 (syntax-ppss)) (nth 3 (syntax-ppss)) (nth 8 (syntax-ppss)) (nth 9 (syntax-ppss))))"
  :expected "(1 34 11 (1))"
  :emacs :match)

 (:name "backquote-basic-unquote"
  :expr "(let ((b '(ba bb bc))) `(a ,b c))"
  :expected "(a (ba bb bc) c)"
  :emacs :match)

 (:name "derived-mode--flush-clears-caches"
  :expr "(let ((a 'clemacs-test-a) (b 'clemacs-test-b)) (put a 'derived-mode--all-parents 7) (put a 'derived-mode--followers (list b)) (put b 'derived-mode--all-parents 9) (derived-mode--flush a) (and (null (get a 'derived-mode--all-parents)) (null (get b 'derived-mode--all-parents)) (null (get a 'derived-mode--followers)) t))"
  :expected "t"
  :emacs :match)

 (:name "mapbacktrace-no-error"
  :expr "(condition-case _e (progn (mapbacktrace (lambda (&rest _f) nil)) t) (error nil))"
  :expected "t"
  :emacs :match)

 (:name "substitute-key-definition-key-basic"
  :expr "(let ((m (make-sparse-keymap))) (substitute-key-definition-key 'foo 'foo 'bar [97] m) (eq (lookup-key m [97]) 'bar))"
  :expected "t"
  :emacs :match)

 (:name "event-modifiers-char-nil"
  :expr "(event-modifiers ?a)"
  :expected "nil"
  :emacs :match)

 (:name "frame-root-window-selected-window"
  :expr "(eq (frame-root-window) (selected-window))"
  :expected "t"
  :emacs :match)

 (:name "default-file-modes-integerp"
  :expr "(integerp (default-file-modes))"
  :expected "t"
  :emacs :match)

 (:name "file-modes-non-nil"
  :expr "(let ((m (file-modes \"lisp/subr.el\"))) (and (integerp m) (> m 0) t))"
  :expected "t"
  :emacs :match)

 (:name "minibuffer-contents-stringp"
  :expr "(stringp (minibuffer-contents))"
  :expected "t"
  :emacs nil)

 (:name "number-at-point-basic"
  :expr "(with-temp-buffer (insert \"x 42 y\") (goto-char 4) (number-at-point))"
  :expected "42"
  :emacs :match)

 (:name "forward-sexp-paren"
  :expr "(with-temp-buffer (insert \"(a b)\") (goto-char 1) (forward-sexp 1) (point))"
  :expected "6"
  :emacs :match)

 (:name "window-end-single-window"
  :expr "(with-temp-buffer (insert \"abc\") (let ((b (current-buffer))) (save-window-excursion (switch-to-buffer b) (window-end))))"
  :expected "4"
  :emacs :match)

 (:name "single-key-description-printable"
  :expr "(single-key-description ?a)"
  :expected "\"a\""
  :emacs :match)

 (:name "event-apply-modifier-control"
  :expr "(event-apply-modifier ?a 'control 26 \"C-\")"
  :expected "1"
  :emacs :match)

 (:name "call-process-region-cat-inserts"
  :expr "(with-temp-buffer (insert \"abc\") (call-process-region (point-min) (point-max) \"cat\" nil t) (buffer-string))"
  :expected "\"abcabc\""
  :emacs :match)

 (:name "call-process-echo-inserts"
  :expr "(with-temp-buffer (list (call-process \"/usr/bin/printf\" nil t nil \"hi\") (buffer-string)))"
  :expected "(0 \"hi\")"
  :emacs :match)

 (:name "start-process-sh-printf-inserts"
  :expr "(with-temp-buffer (let ((p (start-process \"p\" (current-buffer) \"/bin/sh\" \"-c\" \"printf hi\"))) (catch 'done (dotimes (_ 200) (unless (process-live-p p) (throw 'done t)) (accept-process-output p 0.01))) (buffer-string)))"
  :expected "\"hi\\nProcess p finished\\n\""
  :emacs :match)

 (:name "process-mark-advances-with-output"
  :expr "(with-temp-buffer (let ((p (start-process \"p\" (current-buffer) \"/bin/sh\" \"-c\" \"printf hi\"))) (catch 'done (dotimes (_ 200) (unless (process-live-p p) (throw 'done t)) (accept-process-output p 0.01))) (list (buffer-string) (marker-position (process-mark p)) (point-max))))"
  :expected "(\"hi\\nProcess p finished\\n\" 23 23)"
  :emacs :match)

 (:name "process-attributes-has-comm"
  :expr "(and (assq 'comm (process-attributes (emacs-pid))) t)"
  :expected "t"
  :emacs :match)

 (:name "vars-variable-watchers-roundtrip"
  :expr "(progn (setq clemacs--tmp-vw nil) (add-variable-watcher 'clemacs--tmp-vw #'ignore) (add-variable-watcher 'clemacs--tmp-vw #'ignore) (let ((ws (get-variable-watchers 'clemacs--tmp-vw))) (remove-variable-watcher 'clemacs--tmp-vw #'ignore) (list ws (get-variable-watchers 'clemacs--tmp-vw))))"
  :expected "((ignore) nil)"
  :emacs :match)
)
