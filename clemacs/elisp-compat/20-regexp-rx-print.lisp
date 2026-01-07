(in-package #:elisp)

(cl:defvar emacs-version "31.0.50")

(cl:defvar lexical-binding t)

(cl:defvar case-fold-search nil)

(defvar *match-data* nil)
(defvar *match-source-string* nil)
(defvar *string-match-scanner-cache* (cl:make-hash-table :test #'cl:equal))
(defvar *string-match-anchored-scanner-cache* (cl:make-hash-table :test #'cl:equal))

(cl:defun match-data ()
  "Bring-up subset of ELisp `match-data'."
  (and *match-data* (copy-list *match-data*)))

(cl:defun set-match-data (data &optional _reseat _inhibit-read-only)
  "Bring-up subset of ELisp `set-match-data'."
  (declare (cl:ignore _reseat _inhibit-read-only))
  (setf *match-data* (and data (copy-list data)))
  nil)

(cl:defun match-data--translate (delta)
  "Bring-up subset of ELisp `match-data--translate'.

Shift the current match data by DELTA (an integer offset)."
  (unless (integerp delta)
    (error "ELISP:MATCH-DATA--TRANSLATE expects integer, got: %S" delta))
  (when *match-data*
    (setf *match-data*
          (mapcar (lambda (x)
                    (if (integerp x) (+ x delta) x))
                  *match-data*)))
  nil)

(cl:defun match-beginning (n)
  "Bring-up subset of ELisp `match-beginning'."
  (unless (and (integerp n) (<= 0 n))
    (error "ELISP:MATCH-BEGINNING expects non-negative integer, got: %S" n))
  (let ((i (* 2 n)))
    (and *match-data* (< i (length *match-data*)) (nth i *match-data*))))

(cl:defun match-end (n)
  "Bring-up subset of ELisp `match-end'."
  (unless (and (integerp n) (<= 0 n))
    (error "ELISP:MATCH-END expects non-negative integer, got: %S" n))
  (let ((i (1+ (* 2 n))))
    (and *match-data* (< i (length *match-data*)) (nth i *match-data*))))

(cl:defun match-string (n &optional string)
  "Bring-up subset of ELisp `match-string'."
  (unless (and (integerp n) (<= 0 n))
    (error "ELISP:MATCH-STRING expects non-negative integer, got: %S" n))
  (let* ((start (match-beginning n))
         (end (match-end n)))
    (when (or (null start) (null end))
      (return-from match-string nil))
    ;; If STRING is non-nil, Emacs uses match positions as 0-based indices into
    ;; that string (as set by `string-match').
    (cond
     (string
      (substring string start end))
     ;; When the last match came from `string-match', it stashes the searched
     ;; string in `*match-source-string*'.
     (*match-source-string*
      (substring *match-source-string* start end))
     ;; Otherwise, assume the last match came from a buffer regexp operation
     ;; like `looking-at' or `re-search-forward', and use buffer positions.
     (t
      (buffer-substring start end)))))

(cl:defun %elisp-regexp->pcre (regexp)
  "Translate a (very) small subset of Emacs regexps to PCRE.

Key rule: Emacs uses backslash escapes for grouping/alternation
(`\\(...\\)' and `\\|'), while unescaped parens and | are literals.
PCRE uses unescaped parens/| as metacharacters.

So we:
- convert escaped Emacs grouping/alternation to PCRE metacharacters,
- escape otherwise-unescaped PCRE metacharacters to preserve literal meaning,
- translate `\\` and `\\'' anchors to ^/$."
  (let ((regexp (%elisp-string->cl-string regexp)))
    (cl:with-output-to-string (out)
      (labels ((emit-posix-class (name)
                 ;; cl-ppcre does not support POSIX bracket expressions like
                 ;; [[:alpha:]] directly, so approximate the commonly used
                 ;; ones with ASCII ranges.
                 (let ((s (string-downcase name)))
                   (cond
                    ((string= s "alnum") (write-string "0-9A-Za-z" out))
                    ((string= s "alpha") (write-string "A-Za-z" out))
                    ((string= s "digit") (write-string "0-9" out))
                    ((string= s "lower") (write-string "a-z" out))
                    ((string= s "upper") (write-string "A-Z" out))
                    ((string= s "xdigit") (write-string "0-9A-Fa-f" out))
                    ((string= s "space") (write-string "\\s" out))
	                    ((string= s "blank") (write-string " \\t" out))
                    (t
                     ;; Unknown class: fall back to a conservative subset so
                     ;; callers don't explode during bring-up.
                     (write-string "A-Za-z" out))))))
        (loop with i = 0
              with n = (length regexp)
              with in-class = nil
            while (< i n) do
              (let ((ch (char regexp i)))
	               (cond
	                ((char= ch #\\)
	                 (incf i)
	                 (when (>= i n)
	                   (write-char #\\ out)
	                   (return))
	                 (let ((next (char regexp i)))
	                   (case next
	                     (#\( (write-char #\( out))
	                     (#\) (write-char #\) out))
	                     (#\| (write-char #\| out))
	                     (#\{ (write-char #\{ out))
	                     (#\} (write-char #\} out))
	                     ;; Emacs `\\`` and `\\'' mean beginning/end of buffer.
	                     ;; Preserve those semantics even if we later treat `^`/`$`
	                     ;; as line anchors.
	                     (#\` (write-string "\\A" out))
	                     (#\' (write-string "\\z" out))
	                     (otherwise
	                      (write-char #\\ out)
	                      (write-char next out)))))
                 ;; Character classes: preserve [...] structure and make sure we
                 ;; can include a literal `[` inside (used by pp.el).
                 ((and (not in-class) (char= ch #\[))
                  (setf in-class t)
                  (write-char ch out))
                 ((and in-class (char= ch #\]))
                  (setf in-class nil)
                  (write-char ch out))
                 ((and in-class (char= ch #\[))
                  ;; Inside a bracket expression, Emacs regexps can embed
                  ;; POSIX-style character classes like `[:alpha:]'.  cl-ppcre
                  ;; does not accept that syntax, so translate to an ASCII
                  ;; approximation.  The inner `[:...:]' construct should not
                  ;; terminate the outer bracket expression.
                  (cond
                   ((and (< (1+ i) n) (char= (char regexp (1+ i)) #\:))
                    (let ((end (search ":]" regexp :start2 (+ i 2))))
                      (if end
                          (progn
                            (emit-posix-class (subseq regexp (+ i 2) end))
                            (setf i (1+ end)))
                          (progn
                            (write-char #\\ out)
                            (write-char #\[ out)))))
                   (t
                    (write-char #\\ out)
                    (write-char #\[ out))))
	                ;; Escape PCRE metachars that are literals in Emacs regexps.
	                ((and (not in-class) (find ch "()|{}" :test #'char=))
	                 (write-char #\\ out)
	                 (write-char ch out))
	                ;; In Emacs regexps, `^`/`$` are beginning/end of *line*.
	                ;; Approximate using (?:^|(?<=\\n)) and (?:$|(?=\\n)) so we
	                ;; don't have to enable PCRE multiline globally (and can keep
	                ;; `\\``/`\\'' as strict buffer anchors via \\A/\\z).
	                ((and (not in-class) (char= ch #\^))
	                 (write-string "(?:^|(?<=\\n))" out))
	                ((and (not in-class) (char= ch #\$))
	                 (write-string "(?:$|(?=\\n))" out))
	                (t
	                 (write-char ch out))))
	             (incf i))))))

(cl:defun %string-match-scanner (regexp case-fold-search)
  (let* ((regexp (%elisp-string->cl-string regexp))
         (key (list regexp (and case-fold-search t)))
         (cached (gethash key *string-match-scanner-cache*)))
    (or cached
        (setf (gethash key *string-match-scanner-cache*)
              (cl-ppcre:create-scanner (%elisp-regexp->pcre regexp)
                                       :case-insensitive-mode
                                       (and case-fold-search t))))))

(cl:defun %string-match-anchored-scanner (regexp case-fold-search)
  "Return a scanner that only matches at the start of the searched region.

This is used for ELisp `looking-at', which must not search forward past point."
  (let* ((regexp (%elisp-string->cl-string regexp))
         (key (list regexp (and case-fold-search t)))
         (cached (gethash key *string-match-anchored-scanner-cache*)))
    (or cached
        (setf (gethash key *string-match-anchored-scanner-cache*)
              (cl-ppcre:create-scanner
               (concatenate 'cl:string "\\A(?:" (%elisp-regexp->pcre regexp) ")")
               :case-insensitive-mode
               (and case-fold-search t))))))

(cl:defun string-match (regexp string &optional start _inhibit-modify)
  "Bring-up `string-match' using cl-ppcre as a temporary regexp engine."
  (declare (cl:ignore _inhibit-modify))
  (unless (and (stringp regexp) (stringp string))
    (error "ELISP:STRING-MATCH expects strings, got: %S %S" regexp string))
  (let ((start (or start 0))
        (s (%elisp-string->cl-string string)))
    (unless (and (integerp start) (<= 0 start))
      (error "ELISP:STRING-MATCH bad start: %S" start))
    (multiple-value-bind (mstart mend reg-starts reg-ends)
        (cl-ppcre:scan (%string-match-scanner regexp case-fold-search)
                       s
                       :start start
                       ;; cl-ppcre's internal "real start" affects how anchors
                       ;; behave with :start.  Emacs anchors are not relative to
                       ;; the search start, so pin to 0.
                       :real-start-pos 0)
      (if (null mstart)
          (progn
            (setf *match-data* nil
                  *match-source-string* string)
            nil)
          (let ((md nil))
            ;; Build match data in reverse, then NREVERSE to produce:
            ;; (mstart mend g1start g1end g2start g2end ...).
            (push mstart md)
            (push mend md)
            (when reg-starts
              (loop for rs across reg-starts
                    for re across reg-ends
                    do
                      (push (and (integerp rs) (<= 0 rs) rs) md)
                      (push (and (integerp re) (<= 0 re) re) md)))
            (setf *match-data* (nreverse md)
                  *match-source-string* string)
            mstart)))))

(cl:defun string-match-p (regexp string &optional start)
  "Bring-up `string-match-p' (like `string-match' but does not modify match data)."
  (let ((saved-md *match-data*)
        (saved-s *match-source-string*))
    (unwind-protect
        (string-match regexp string start)
      (setf *match-data* saved-md
            *match-source-string* saved-s))))

(cl:defun regexp-quote (string &optional _lax)
  "Bring-up subset of the C primitive `regexp-quote'."
  (declare (cl:ignore _lax))
  (unless (stringp string)
    (error "ELISP:REGEXP-QUOTE expects a string, got: %S" string))
  ;; Preserve unibyte vs multibyte: return a unibyte string iff STRING is
  ;; unibyte (and the output stays byte-representable).
  (let* ((want-unibyte (unibyte-string-p string))
         (s (%elisp-string->cl-string string))
         (codes (make-array 0 :element-type 'integer :adjustable t :fill-pointer 0)))
    (labels ((emit (code)
               (vector-push-extend code codes)))
      (loop for ch across s do
        ;; Match Emacs: do NOT escape `|', `(', `)', `{', or `}'.
        (when (find ch "\\.[]*+?^$" :test #'char=)
          (emit (char-code #\\)))
        (emit (%elisp-char-code ch)))
      (if want-unibyte
          (let ((out (%make-unibyte-string (length codes))))
            (dotimes (i (length codes))
              (let ((b (aref codes i)))
                (unless (and (integerp b) (<= 0 b 255))
                  (error "ELISP:REGEXP-QUOTE cannot encode byte: %S" b))
                (setf (aref out i) b)))
            out)
          (let ((out (cl:make-string (length codes))))
            (dotimes (i (length codes))
              (setf (char out i) (%elisp-code->char (aref codes i))))
            out)))))

(cl:defun %rx--regexp-quote (s)
  "Very small subset of Emacs's `regexp-quote'."
  (let ((s (%elisp-string->cl-string s)))
    (cl:with-output-to-string (out)
      (loop for ch across s do
        (when (find ch "\\.[]*+?^$" :test #'char=)
          (write-char #\\ out))
        (write-char ch out)))))

(cl:defun %rx--lookup-definition (name)
  (let ((d (and (symbolp name) (get name 'rx-definition))))
    (cond
     ((null d) nil)
     ((and (consp d) (null (cdr d))) (car d))
     (t (cons (intern ":" (find-package "ELISP")) d)))))

(cl:defun %rx--translate (form)
  ;; Return an Emacs regexp string (not PCRE). This is intentionally tiny and
  ;; only grows as startup checkpoints demand it.
  (labels ((op-name (s) (and (symbolp s) (cl:symbol-name s)))
           (op= (s name) (and (symbolp s) (string= (cl:symbol-name s) name)))
           (group (s) (concatenate 'cl:string "\\(?:" s "\\)"))
           (capture (s) (concatenate 'cl:string "\\(" s "\\)"))
           (emit (x)
             (cond
              ((null x) "")
              ((stringp x) (%rx--regexp-quote x))
              ((symbolp x)
               (let ((def (%rx--lookup-definition x)))
                 (cond
                  (def (%rx--translate def))
                  ((op= x "STRING-START") "\\`")
                  ((op= x "STRING-END") "\\'")
                  ((memq x '(nonl not-newline any)) ".")
                  (t (error "ELISP:rx unsupported symbol: %S" x)))))
              ((consp x)
               (let ((op (car x))
                     (args (cdr x)))
                 (cond
                  ;; Sequence.
                  ((or (op= op ":") (op= op "SEQ"))
                   (apply #'concatenate 'cl:string (mapcar #'emit args)))
                  ;; Capturing group.
                  ((op= op "GROUP")
                   (capture (apply #'concatenate 'cl:string (mapcar #'emit args))))
                  ;; Capturing group (explicit group number): treat like GROUP.
                  ((op= op "GROUP-N")
                   (when (and args (integerp (car args)))
                     (setf args (cdr args)))
                   (capture (apply #'concatenate 'cl:string (mapcar #'emit args))))
                  ;; Alternation.
                  ((or (op= op "|") (op= op "OR"))
                   (group
                    (cl:with-output-to-string (out)
                      (loop for a in args
                            for firstp = t then nil do
                              (unless firstp (write-string "\\|" out))
                              (write-string (emit a) out)))))
                  ;; One-or-more.
                  ((op= op "+")
                   (cond
                    ;; Reader quirk: inside symbols, ELisp allows `+?' (used by
                    ;; `rx'), but our current reader treats `?' as a character
                    ;; literal macro-char and splits `+?' into `+' and a char
                    ;; object. In `ert-x.el` this yields forms like (+ 32 PAT).
                    ;; Treat that as `+?' for bring-up.
                    ((and (= (length args) 2)
                          (integerp (car args)))
                     (concatenate 'cl:string
                                  (group (apply #'concatenate 'cl:string
                                                (mapcar #'emit (cdr args))))
                                  "+?"))
                    ((null args)
                     (error "ELISP:rx (+ ...) expects args, got: %S" x))
                    (t
                     (concatenate 'cl:string
                                  (group (apply #'concatenate 'cl:string
                                                (mapcar #'emit args)))
                                  "+"))))
                  ;; One-or-more (non-greedy).
                  ((op= op "+?")
                   (cond
                    ((null args)
                     (error "ELISP:rx (+? ...) expects args, got: %S" x))
                    (t
                     (concatenate 'cl:string
                                  (group (apply #'concatenate 'cl:string
                                                (mapcar #'emit args)))
                                  "+?"))))
                  ;; Zero-or-more.
                  ((op= op "*")
                   (cond
                    ;; See `+` reader quirk note above.
                    ((and (>= (length args) 2)
                          (integerp (car args)))
                     (concatenate 'cl:string
                                  (group (apply #'concatenate 'cl:string
                                                (mapcar #'emit (cdr args))))
                                  "*?"))
                    ((null args)
                     (error "ELISP:rx (* ...) expects args, got: %S" x))
                    (t
                     (concatenate 'cl:string
                                  (group (apply #'concatenate 'cl:string
                                                (mapcar #'emit args)))
                                  "*"))))
                  ;; Zero-or-more (non-greedy).
                  ((op= op "*?")
                   (cond
                    ((null args)
                     (error "ELISP:rx (*? ...) expects args, got: %S" x))
                    (t
                     (concatenate 'cl:string
                                  (group (apply #'concatenate 'cl:string
                                                (mapcar #'emit args)))
                                  "*?"))))
                  ;; Embed an already-formed regexp.
                  ((op= op "REGEXP")
                   (cond
                    ((/= (length args) 1)
                     (error "ELISP:rx (regexp ...) expects 1 arg, got: %S" x))
                    (t
                     (let ((s (car args)))
                       (unless (stringp s)
                         (error "ELISP:rx (regexp ...) expects string, got: %S" s))
                       (group (%elisp-string->cl-string s))))))
                  ;; (syntax word) / (syntax symbol): approximate for bring-up.
                  ((op= op "SYNTAX")
                   (let ((kind (car args)))
                     (cond
                      ((or (eq kind 'word) (eq kind 'symbol))
                        ;; Keep this within the subset understood by
                        ;; %elisp-regexp->pcre: POSIX classes only inside [...]
                        ;; and ASCII-only approximations.
                        "[[:alnum:]_]")
                      (t
                       (error "ELISP:rx (syntax ...) unsupported: %S" x)))))
                  (t
                   (error "ELISP:rx unsupported form: %S" x)))))
              (t
               (error "ELISP:rx unsupported object: %S" x)))))
    (emit form)))

(cl:defun %rx--runtime (forms)
  (cond
   ((null forms) "")
   ((null (cdr forms)) (%rx--translate (car forms)))
   (t
    (%rx--translate (cons (intern ":" (find-package "ELISP")) forms)))))

(cl:defmacro rx (&rest forms)
  "Bring-up subset of Emacs's `rx' macro."
  `(%rx--runtime ',forms))

(cl:defmacro rx-define (name &rest definition)
  "Bring-up subset of Emacs's `rx-define'."
  `(progn
     (put ',name 'rx-definition ',definition)
     ',name))

(cl:defun string-search (needle haystack &optional start)
  "Bring-up subset of the C primitive `string-search'."
  (unless (and (stringp needle) (stringp haystack))
    (error "ELISP:STRING-SEARCH expects strings, got: ~S ~S" needle haystack))
  (let* ((n (%elisp-string->cl-string needle))
         (h (%elisp-string->cl-string haystack))
         (start (or start 0)))
    (unless (and (integerp start) (<= 0 start) (<= start (length h)))
      (error "ELISP:STRING-SEARCH bad start: ~S" start))
    (search n h :start2 start :test #'char=)))

(cl:defvar print-escape-newlines nil)
(cl:defvar print-escape-control-characters nil)

(cl:defun prin1-to-string (object &optional _noescape)
  "Bring-up subset of ELisp `prin1-to-string'.

This is only intended to be readable by our ELisp `read-from-string'."
  (declare (cl:ignore _noescape))
  (labels ((sym-name (s)
             (cond
              ((eq s nil) "nil")
              ((eq s t) "t")
              ((eq (symbol-package s) (find-package "KEYWORD"))
               (concatenate 'cl:string ":" (string-downcase (cl:symbol-name s))))
              (t (string-downcase (cl:symbol-name s)))))
           (emit-string (s)
             (cl:with-output-to-string (out)
               (write-char #\" out)
               (flet ((emit-hex (code)
                        (cl:format out "\\\\x~2,'0x" code)))
                 (cond
                  ((unibyte-string-p s)
                   (dotimes (i (length s))
                     (let ((b (aref s i)))
                       (case b
                         (#.(char-code #\") (write-string "\\\"" out))
                         (#.(char-code #\\) (write-string "\\\\" out))
                         (#.(char-code #\Newline)
                          (if print-escape-newlines
                              (write-string "\\n" out)
                              (write-char #\Newline out)))
                         (#.(char-code #\Tab)
                          (if print-escape-control-characters
                              (write-string "\\t" out)
                              (write-char #\Tab out)))
                         (#.(char-code #\Return)
                          (if print-escape-control-characters
                              (write-string "\\r" out)
                              (write-char #\Return out)))
                         (#.(char-code #\Backspace)
                          (if print-escape-control-characters
                              (write-string "\\b" out)
                              (write-char #\Backspace out)))
                         (#.(char-code #\Page)
                          (if print-escape-control-characters
                              (write-string "\\f" out)
                              (write-char #\Page out)))
                         (otherwise
                          (cond
                           ((and (<= 32 b 126) (not (member b (list (char-code #\") (char-code #\\)))))
                            (write-char (code-char b) out))
                           (t (emit-hex b)))))))
                   (write-char #\" out))
                  ((stringp s)
                   (dotimes (i (length s))
                     (let ((ch (char s i)))
                       (case ch
                         (#\" (write-string "\\\"" out))
                         (#\\ (write-string "\\\\" out))
                         (#\Newline
                          (if print-escape-newlines
                              (write-string "\\n" out)
                              (write-char #\Newline out)))
                         (#\Tab
                          (if print-escape-control-characters
                              (write-string "\\t" out)
                              (write-char #\Tab out)))
                         (#\Return
                          (if print-escape-control-characters
                              (write-string "\\r" out)
                              (write-char #\Return out)))
                         (#\Backspace
                          (if print-escape-control-characters
                              (write-string "\\b" out)
                              (write-char #\Backspace out)))
                         (#\Page
                          (if print-escape-control-characters
                              (write-string "\\f" out)
                              (write-char #\Page out)))
                         (otherwise
                          (let ((cc (char-code ch)))
                            (cond
                             ((<= 32 cc 126) (write-char ch out))
                             ((<= cc 255) (emit-hex cc))
                             (t (cl:format out "\\\\u~4,'0x" cc))))))))
                   (write-char #\" out))
                  (t
                   (cl:error "ELISP:PRIN1-TO-STRING expected string, got: ~S"
                             (type-of s)))))))
           (emit (x)
             (cond
              ((null x) "nil")
              ((eq x t) "t")
              ((symbolp x) (sym-name x))
              ((integerp x) (cl:princ-to-string x))
              ((characterp x) (emit-string (string x)))
              ((or (unibyte-string-p x) (cl:stringp x)) (emit-string x))
              ((and (vectorp x) (not (stringp x)))
               (cl:with-output-to-string (out)
                 (write-char #\[ out)
                 (dotimes (i (length x))
                   (when (> i 0) (write-char #\Space out))
                   (write-string (emit (aref x i)) out))
                 (write-char #\] out)))
              ((consp x)
               (cond
                ((and (eq (car x) 'quote) (consp (cdr x)) (null (cddr x)))
                 (cl:with-output-to-string (out)
                   (write-char #\' out)
                   (write-string (emit (cadr x)) out)))
                ((and (eq (car x) 'function) (consp (cdr x)) (null (cddr x)))
                 (cl:with-output-to-string (out)
                   (write-string "#'" out)
                   (write-string (emit (cadr x)) out)))
                (t
               (cl:with-output-to-string (out)
                 (write-char #\( out)
                 (labels ((walk (cell firstp)
                            (cond
                             ((null cell) nil)
                             ((consp cell)
                              (unless firstp (write-char #\Space out))
                              (write-string (emit (car cell)) out)
                              (walk (cdr cell) nil))
                             (t
                              (write-string " . " out)
                              (write-string (emit cell) out)))))
                   (walk x t))
                 (write-char #\) out)))
                ))
              ;; Emacs expects hash-tables to be printable/readable when the
              ;; feature is available. For bring-up, keep it simple: print an
              ;; empty hash-table in a read-time-eval form so `read-from-string'
              ;; can reconstruct one.
              ((cl:hash-table-p x) "#.(make-hash-table)")
              (t (cl:prin1-to-string x)))))
    (let ((print-escape-newlines (and (boundp 'print-escape-newlines) print-escape-newlines))
          (print-escape-control-characters
            (and (boundp 'print-escape-control-characters) print-escape-control-characters)))
      (emit object))))

(cl:defun princ-to-string (object)
  "Bring-up subset of ELisp `princ-to-string'."
  (cond
   ((null object) "nil")
   ((eq object t) "t")
   ((symbolp object) (symbol-name object))
   ((stringp object) object)
   ((integerp object) (cl:princ-to-string object))
   ((characterp object) (string object))
   (t (cl:princ-to-string object))))


(cl:defun read-from-string (string &optional start end)
  "Bring-up subset of ELisp `read-from-string'.

Return (OBJECT . POSITION) where POSITION is the index of the first unread
character in STRING."
  (unless (stringp string)
    (error "ELISP:READ-FROM-STRING expects a string, got: %S" string))
  (let* ((s (%elisp-string->cl-string string))
         (start (or start 0))
         (end (or end (length s))))
    (unless (and (integerp start) (<= 0 start))
      (error "ELISP:READ-FROM-STRING bad start: %S" start))
    (unless (and (integerp end) (<= start end) (<= end (length s)))
      (error "ELISP:READ-FROM-STRING bad end: %S" end))
    (let* ((sub (subseq s start end)))
      (multiple-value-bind (sanitized insertions)
          (elisp::%sanitize-elisp-source/colon-tokens sub)
        (let ((*package* (find-package "ELISP"))
              (*readtable* (elisp::%ensure-elisp-readtable))
              (*read-eval* t))
          (multiple-value-bind (obj pos)
              (cl:read-from-string sanitized nil :eof)
            (when (eq obj :eof)
              (error "ELISP:READ-FROM-STRING EOF"))
            (let* ((ins-before (%count-insertions-before insertions pos))
                   (pos* (- pos ins-before)))
              (cons obj (+ start pos*)))))))))

(cl:defun string-to-number (string)
  "Bring-up subset of ELisp `string-to-number'."
  (unless (stringp string)
    (error "ELISP:STRING-TO-NUMBER expects string, got: ~S" string))
  (handler-case
      (parse-integer (%elisp-string->cl-string string) :junk-allowed t)
    (cl:error () 0)))

(cl:defun string-to-char (string)
  "Bring-up subset of ELisp `string-to-char'."
  (unless (stringp string)
    (error "ELISP:STRING-TO-CHAR expects string, got: ~S" string))
  (if (zerop (length string))
      0
      (aref string 0)))

(cl:defun copy-sequence (sequence)
  "ELisp-ish COPY-SEQUENCE."
  (typecase sequence
    (null nil)
    (cons (copy-list sequence))
    (cl:string (copy-seq sequence))
    (unibyte-string (copy-seq sequence))
    (vector (copy-seq sequence))
    (t (error "ELISP:COPY-SEQUENCE unsupported type: ~S" (type-of sequence)))))

(cl:defun make-hash-table (&rest args &key (test 'eql) &allow-other-keys)
  "ELisp-ish MAKE-HASH-TABLE.

Emacs Lisp accepts `:test' values like 'eq/'eql/'equal/'equalp. We map
`equal' to CL:EQUALP to get vector element semantics, which is a closer
match to Elisp than CL:EQUAL.

  Also supports SBCL weak hash tables via Emacs's `:weakness' values (e.g. 'key)."
  (unless (symbolp test)
    (error "ELISP:MAKE-HASH-TABLE only supports symbolic :test, got: ~S" test))
  (let* ((mapped-test
           (cond
            ((or (eq test 'eq) (eq test 'cl:eq)) 'cl:eq)
            ((or (eq test 'eql) (eq test 'cl:eql)) 'cl:eql)
            ((or (eq test 'equal) (eq test 'cl:equal)) 'cl:equalp)
            ((or (eq test 'equalp) (eq test 'cl:equalp)) 'cl:equalp)
            (t (error "ELISP:MAKE-HASH-TABLE unsupported :test: ~S" test))))
         ;; Always include the mapped test, even if SBCL doesn't retain :TEST in
         ;; &REST when &KEY is present.
         (out (list :test mapped-test)))
    (loop for (k v) on args by (cl:function cl:cddr) do
      (cond
       ((eq k :test) nil)
       ((eq k :weakness)
        (let ((wk
                (cond
                 ((null v) nil)
                 ((eq v t) :key-and-value)
                 ((eq v :key) :key)
                 ((eq v :value) :value)
                 ((eq v :key-or-value) :key-or-value)
                 ((eq v :key-and-value) :key-and-value)
                 ((eq v 'key) :key)
                 ((eq v 'value) :value)
                 ((eq v 'key-or-value) :key-or-value)
                 ((eq v 'key-and-value) :key-and-value)
                 (t (error "ELISP:MAKE-HASH-TABLE unsupported :weakness: ~S" v)))))
          (when wk
            (setf out (nconc out (list :weakness wk))))))
       ((or (eq k :size) (eq k :rehash-size) (eq k :rehash-threshold))
        (setf out (nconc out (list k v))))
       (t nil)))
    (apply #'cl:make-hash-table out)))

(cl:defun puthash (key value table)
  "ELisp-ish PUTHASH."
  (setf (gethash key table) value)
  value)

(defparameter features nil)

(cl:defun featurep (feature)
  "Stub for ELisp `featurep'."
  (and (cl:member feature features :test 'eq) t))

(cl:defun provide (feature &optional _subfeatures)
  "Stub for ELisp `provide'."
  (declare (cl:ignore _subfeatures))
  (pushnew feature features :test 'eq)
  feature)

(cl:defun require (feature &optional _filename _noerror)
  "Stub for ELisp `require'.

Currently does not load code; it only records FEATURE as provided."
  (declare (cl:ignore _filename _noerror))
  (unless (featurep feature)
    (provide feature))
  feature)

(cl:defmacro |`| (structure)
  "ELisp backquote reader form: (` STRUCTURE) -> (backquote STRUCTURE)."
  `(backquote ,structure))

(cl:defun backquote-list* (&rest args)
  "Run-time helper used by `lisp/emacs-lisp/backquote.el' expansions."
  (apply #'cl:list* args))

(cl:defun append (&rest seqs)
  "ELisp-ish APPEND.

Supports lists and vectors (and strings as a sequence of characters).
This is sufficient for `lisp/emacs-lisp/backquote.el', which uses
`(append VEC ())' to turn a vector into a list of its elements."
  (labels ((seq->list (x &key (copy t))
             (cond
              ((null x) nil)
              ((consp x) (if copy (copy-list x) x))
              ((vectorp x) (coerce x 'list))
              ((stringp x)
               (loop for i from 0 below (length x)
                     collect (aref x i)))
              (t (error "ELISP:APPEND unsupported type: ~S" (type-of x))))))
    (cond
     ((null seqs) nil)
     ((null (cdr seqs)) (seq->list (car seqs)))
     (t
      (let* ((last (car (last seqs)))
             (prefix (butlast seqs))
             (acc nil))
        (dolist (s prefix)
          (setf acc (nconc acc (seq->list s))))
        (cond
         ((listp last)
          (nconc acc last))
         ((or (vectorp last) (stringp last))
          (nconc acc (seq->list last)))
         (t
          (if (null acc)
              last
              (progn
                (setf (cdr (last acc)) last)
                acc)))))))))

(cl:defun mapcar (function &rest sequences)
  "ELisp-ish MAPCAR.

In Emacs, `mapcar' accepts lists and sequences (vectors and strings), and
terminates at the shortest sequence."
  (labels ((init (seq)
             (cond
              ((null seq) (list :list nil))
              ((consp seq) (list :list seq))
              ((vectorp seq) (list :vector seq 0 (length seq)))
              ((unibyte-string-p seq) (list :unibyte seq 0 (length seq)))
              ((cl:stringp seq) (list :string seq 0 (length seq)))
              (t (error "ELISP:MAPCAR unsupported sequence: ~S" (type-of seq)))))
           (donep (st)
             (ecase (first st)
               (:list (null (second st)))
               ((:vector :unibyte :string) (>= (third st) (fourth st)))))
           (elem (st)
             (ecase (first st)
               (:list (car (second st)))
               (:vector (aref (second st) (third st)))
               (:unibyte (aref (second st) (third st)))
               (:string (%elisp-char-code (char (second st) (third st))))))
           (advance (st)
             (ecase (first st)
               (:list (setf (second st) (cdr (second st))))
               ((:vector :unibyte :string) (incf (third st))))
             st))
    (let ((states (cl:mapcar #'init sequences))
          (out nil))
      (loop while (and states (not (cl:some #'donep states))) do
        (push (cl:apply function (cl:mapcar #'elem states)) out)
        (dolist (st states)
          (advance st)))
      (nreverse out))))

(cl:defun mapconcat (function sequence separator)
  "Bring-up subset of ELisp `mapconcat'.

Supports lists, vectors, and strings (including unibyte strings)."
  (unless (stringp separator)
    (error "ELISP:MAPCONCAT expects string SEPARATOR, got: ~S" separator))
  (let* ((len
           (cond
            ((null sequence) 0)
            ((consp sequence) (length sequence))
            ((vectorp sequence) (length sequence))
            ((stringp sequence) (length sequence))
            (t (error "ELISP:MAPCONCAT unsupported sequence: ~S" (type-of sequence)))))
         (start* 0)
         (end* len))
    (labels ((elt-at (i)
               (cond
                ((consp sequence) (nth i sequence))
                ((null sequence) (error "ELISP:MAPCONCAT internal bug (elt-at nil)"))
                (t (aref sequence i)))))
      (let ((parts nil)
            (first t))
        (loop for i from start* below end* do
          (let ((s (funcall function (elt-at i))))
            (unless (stringp s)
              (error "ELISP:MAPCONCAT function must return string, got: ~S" s))
            (if first
                (progn
                  (push s parts)
                  (setf first nil))
                (progn
                  (push separator parts)
                  (push s parts)))))
        (apply #'concat (nreverse parts))))))

(cl:defun seq-filter (predicate sequence)
  "Bring-up subset of ELisp `seq-filter'.

Supports lists, vectors, and strings (including unibyte strings)."
  (cond
   ((null sequence) nil)
   ((consp sequence)
    (let ((out nil))
      (dolist (x sequence)
        (when (funcall predicate x)
          (push x out)))
      (nreverse out)))
   ((vectorp sequence)
    (coerce (seq-filter predicate (coerce sequence 'list)) 'vector))
   ((stringp sequence)
    ;; Emacs' seq.el returns a list for string inputs (not a string).
    (let ((out nil))
      (dotimes (i (length sequence))
        (let ((code (aref sequence i)))
          (when (funcall predicate code)
            (push code out))))
      (nreverse out)))
   (t
    (error "ELISP:SEQ-FILTER unsupported sequence: ~S" (type-of sequence)))))

(cl:defmacro eval-when-compile (&rest body)
  "Bring-up stub for ELisp `eval-when-compile'.

Like Emacs' definition in `lisp/emacs-lisp/byte-run.el', this evaluates BODY
at macroexpansion time and returns the result as a quoted constant."
  (list 'quote (eval (cons 'progn body) lexical-binding)))

(cl:defmacro eval-and-compile (&rest body)
  "Bring-up stub for ELisp `eval-and-compile'.

Like Emacs' definition in `lisp/emacs-lisp/byte-run.el', this evaluates BODY
at macroexpansion time and returns the result as a quoted constant."
  (list 'quote (eval (cons 'progn body) lexical-binding)))

(cl:defmacro let-when-compile (bindings &rest body)
  "Bring-up stub for ELisp `let-when-compile'.

Like `let*', but allow for macroexpansion-time optimization.

Each BINDINGS value form is evaluated at macroexpansion time (like `let*').
BODY is then macroexpanded (via `macroexpand-all') in an environment where
the bound variables are dynamically visible, so `eval-when-compile' forms can
turn them into quoted constants."
  (labels ((lwc-step (bs)
             (if (null bs)
                 (macroexpand-all (macroexp-progn body)
                                  macroexpand-all-environment)
               (let* ((binding (car bs))
                      (var (car binding))
                      (expr (cadr binding)))
                 (cl:progv (list var) (list (eval expr lexical-binding))
                   (lwc-step (cdr bs)))))))
    (lwc-step bindings)))
