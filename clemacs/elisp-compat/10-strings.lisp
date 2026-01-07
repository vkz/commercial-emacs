(in-package #:elisp)

(cl:defun char-to-string (ch)
  "Bring-up subset of ELisp `char-to-string'."
  (cond
   ((integerp ch) (string (%elisp-code->char ch)))
   ((characterp ch) (string ch))
   (t (error "ELISP:CHAR-TO-STRING expects character code, got: ~S" ch))))

(cl:defun concat (&rest parts)
  "Stub for ELisp `concat'."
  ;; Minimal type-correctness: if all emitted character codes are ASCII, return a
  ;; unibyte string; otherwise return a multibyte CL string.
  (let ((codes (make-array 0 :element-type 'integer :adjustable t :fill-pointer 0))
        (need-multibyte nil)
        (out-intervals nil)
        (out-len 0))
    (labels ((emit-code (code)
               (vector-push-extend code codes)
               (incf out-len)
               (when (or (%raw-byte-char-code-p code) (>= code 128))
                 (setf need-multibyte t)))
             (emit-string-intervals (s start)
               (let ((intervals (elisp::%string-text-properties s)))
                 (when intervals
                   (setf out-intervals
                         (nconc out-intervals
                                (loop for iv in intervals
                                      for iv-s = (elisp::text-prop-interval-start iv)
                                      for iv-e = (elisp::text-prop-interval-end iv)
                                      collect (elisp::make-text-prop-interval
                                               :start (+ start iv-s)
                                               :end (+ start iv-e)
                                               :plist (elisp::text-prop-interval-plist iv))))))))
             (emit-string (s)
               (emit-string-intervals s out-len)
               (cond
                ((unibyte-string-p s)
                 (dotimes (i (length s))
                   (emit-code (aref s i))))
                (t
                 (dotimes (i (length s))
                   (emit-code (%elisp-char-code (char s i)))))))
             (emit-object (o)
               ;; Force multibyte for non-string objects to avoid accidental
               ;; unibyte/encoding surprises during bring-up.
               (emit-string (string-to-multibyte (princ-to-string o)))))
      (dolist (p parts)
        (typecase p
          (null nil)
          ((or cl:string unibyte-string) (emit-string p))
          (character (emit-code (char-code p)))
          (integer (emit-code p))
          (t (emit-object p))))
      (if (not need-multibyte)
          (let ((out (%make-unibyte-string (length codes))))
            (dotimes (i (length codes))
              (setf (aref out i) (aref codes i)))
            (when out-intervals
              (elisp::%set-string-text-properties out out-intervals))
            out)
          (let ((out (cl:make-string (length codes))))
            (dotimes (i (length codes))
              (setf (char out i) (%elisp-code->char (aref codes i))))
            (when out-intervals
              (elisp::%set-string-text-properties out out-intervals))
            out)))))

(cl:defun vconcat (&rest seqs)
  "Bring-up subset of ELisp `vconcat'."
  (let ((out nil))
    (dolist (s seqs)
      (cond
       ((null s) nil)
       ((vectorp s)
        (dotimes (i (length s))
          (push (aref s i) out)))
       ((stringp s)
        (dotimes (i (length s))
          (push (aref s i) out)))
       ((consp s)
        (dolist (x s) (push x out)))
       (t
        (error "ELISP:VCONCAT unsupported sequence: ~S" (type-of s)))))
    (coerce (nreverse out) 'vector)))

(cl:defun downcase (s)
  "Bring-up subset of ELisp `downcase'."
  (unless (stringp s)
    (error "ELISP:DOWNCASE expects a string, got: ~S" s))
  (cond
   ((unibyte-string-p s)
    (let ((out (%make-unibyte-string (length s))))
      (dotimes (i (length s))
        (let ((b (aref s i)))
          (setf (aref out i)
                (cond
                 ((<= (char-code #\A) b (char-code #\Z)) (+ b 32))
                 (t b)))))
      out))
   (t (string-downcase s))))

(cl:defun upcase (s)
  "Bring-up subset of ELisp `upcase'."
  (unless (stringp s)
    (error "ELISP:UPCASE expects a string, got: ~S" s))
  (cond
   ((unibyte-string-p s)
    (let ((out (%make-unibyte-string (length s))))
      (dotimes (i (length s))
        (let ((b (aref s i)))
          (setf (aref out i)
                (cond
                 ((<= (char-code #\a) b (char-code #\z)) (- b 32))
                 (t b)))))
      out))
   (t (string-upcase s))))

(cl:defun string= (a b)
  "ELisp-ish STRING=.

Unlike CL:STRING-EQUAL, Emacs's `string-equal' is case-sensitive (an alias of
`string=')."
  (let ((a (if (symbolp a) (symbol-name a) a))
        (b (if (symbolp b) (symbol-name b) b)))
    (unless (and (stringp a) (stringp b))
      (error "ELISP:STRING= expects strings or symbols, got: ~S ~S" a b))
    (cond
     ((and (unibyte-string-p a) (unibyte-string-p b))
      (and (= (length a) (length b))
           (loop for i from 0 below (length a)
                 always (= (aref a i) (aref b i)))))
     ((and (cl:stringp a) (cl:stringp b))
      (cl:string= a b))
     (t
      ;; Match Emacs behavior: compare after promoting unibyte to multibyte.
      (cl:string=
       (string-to-multibyte a)
       (string-to-multibyte b))))))

(cl:defun string-equal (a b)
  "ELisp-ish STRING-EQUAL (case-sensitive; alias of `string=')."
  (string= a b))

(cl:defun string-equal-ignore-case (a b)
  "Bring-up subset of ELisp `string-equal-ignore-case'."
  (let ((a (if (symbolp a) (symbol-name a) a))
        (b (if (symbolp b) (symbol-name b) b)))
    (unless (and (stringp a) (stringp b))
      (error "ELISP:STRING-EQUAL-IGNORE-CASE expects strings or symbols, got: ~S ~S" a b))
    (string= (downcase a) (downcase b))))

(cl:defun string-empty-p (string)
  "Bring-up subset of ELisp `string-empty-p'."
  (unless (stringp string)
    (error "ELISP:STRING-EMPTY-P expects a string, got: ~S" string))
  (zerop (length string)))

(cl:defun %plist-put-preserve (plist key value)
  (loop for cell on plist by #'cddr do
    (when (eq (car cell) key)
      (setf (cadr cell) value)
      (return plist)))
  (append plist (list key value)))

(cl:defun %plist-remprop-preserve (plist key)
  (let ((head plist)
        (prev nil)
        (cell plist))
    (loop while cell do
      (if (eq (car cell) key)
          (progn
            (if prev
                (setf (cddr prev) (cddr cell))
                (setf head (cddr cell)))
            (return head))
          (progn
            (setf prev cell)
            (setf cell (cddr cell)))))
    head))

(cl:defun %plist-equal-as-set (a b)
  "Return non-nil when plists A and B have the same key/value pairs.

The comparison ignores key order."
  (cond
   ((and (null a) (null b)) t)
   ((or (null a) (null b)) nil)
   ((or (not (listp a)) (not (listp b))) (equal a b))
   (t
    (let ((keys-a nil)
          (keys-b nil))
      (loop for (k _v) on a by #'cddr do (push k keys-a))
      (loop for (k _v) on b by #'cddr do (push k keys-b))
      (when (/= (length keys-a) (length keys-b))
        (return-from %plist-equal-as-set nil))
      (dolist (k keys-a t)
        (unless (equal (plist-get a k) (plist-get b k))
          (return-from %plist-equal-as-set nil)))))))

(cl:defvar *buffer-text-properties*
  (cl:make-hash-table :test 'eq))

(cl:defun %buffer-text-properties (buffer)
  (gethash buffer *buffer-text-properties*))

(cl:defun %set-buffer-text-properties (buffer intervals)
  (setf (gethash buffer *buffer-text-properties*) intervals)
  buffer)

(cl:defun %clear-buffer-text-properties (buffer)
  (remhash buffer *buffer-text-properties*)
  buffer)

(cl:defun %intervals-properties-at (pos intervals)
  (let ((out nil))
    ;; Apply intervals in order, preserving key position on updates.
    (dolist (iv intervals)
      (when (and (<= (elisp::text-prop-interval-start iv) pos)
                 (< pos (elisp::text-prop-interval-end iv)))
        (loop for (k v) on (elisp::text-prop-interval-plist iv) by #'cddr do
          (setf out (if (null v)
                        (%plist-remprop-preserve out k)
                        (%plist-put-preserve out k v))))))
    out))

(cl:defun %intervals-remove-range (intervals start end)
  "Return INTERVALS with any overlap with [START,END) removed.

If an interval overlaps the range, keep the non-overlapping left/right
portions (split as needed). START/END use the same coordinate system as the
intervals (string: 0-based, buffer: 1-based)."
  (let ((out nil))
    (dolist (iv intervals)
      (let* ((iv-s (elisp::text-prop-interval-start iv))
             (iv-e (elisp::text-prop-interval-end iv))
             (plist (elisp::text-prop-interval-plist iv)))
        (cond
         ;; No overlap.
         ((or (<= iv-e start) (<= end iv-s))
          (push iv out))
         (t
          ;; Left piece.
          (when (< iv-s start)
            (push (elisp::make-text-prop-interval :start iv-s :end start :plist plist) out))
          ;; Right piece.
          (when (< end iv-e)
            (push (elisp::make-text-prop-interval :start end :end iv-e :plist plist) out))))))
    (nreverse out)))

(cl:defun %buffer-intervals-insert (intervals at len)
  "Return buffer text property INTERVALS after inserting LEN chars at AT.

AT is a 1-based buffer position.  Inserted text does not inherit surrounding
buffer properties (plain `insert' semantics)."
  (unless (and (integerp at) (integerp len) (plusp len))
    (error "ELISP:%BUFFER-INTERVALS-INSERT bad args: ~S ~S" at len))
  (let ((out nil))
    (dolist (iv intervals)
      (let* ((iv-s (elisp::text-prop-interval-start iv))
             (iv-e (elisp::text-prop-interval-end iv))
             (plist (elisp::text-prop-interval-plist iv)))
        (cond
         ;; Entirely before insertion point.
         ((<= iv-e at)
          (push iv out))
         ;; Entirely after insertion point.
         ((>= iv-s at)
          (push (elisp::make-text-prop-interval
                 :start (+ iv-s len)
                 :end (+ iv-e len)
                 :plist plist)
                out))
         ;; Interval spans insertion point: split without inheriting into the
         ;; inserted range.
         (t
          (push (elisp::make-text-prop-interval :start iv-s :end at :plist plist) out)
          (push (elisp::make-text-prop-interval
                 :start (+ at len)
                 :end (+ iv-e len)
                 :plist plist)
                out)))))
    (nreverse out)))

(cl:defun %buffer-intervals-delete (intervals start end)
  "Return buffer text property INTERVALS after deleting [START,END).

START/END are 1-based buffer positions."
  (unless (and (integerp start) (integerp end) (<= start end))
    (error "ELISP:%BUFFER-INTERVALS-DELETE bad args: ~S ~S" start end))
  (let ((len (- end start)))
    (when (zerop len)
      (return-from %buffer-intervals-delete intervals))
    (let ((out nil))
      (dolist (iv intervals)
        (let* ((iv-s (elisp::text-prop-interval-start iv))
               (iv-e (elisp::text-prop-interval-end iv))
               (plist (elisp::text-prop-interval-plist iv)))
          (cond
           ;; Entirely before deleted range.
           ((<= iv-e start)
            (push iv out))
           ;; Entirely after deleted range.
           ((>= iv-s end)
            (push (elisp::make-text-prop-interval
                   :start (- iv-s len)
                   :end (- iv-e len)
                   :plist plist)
                  out))
           (t
            ;; Left piece.
            (when (< iv-s start)
              (push (elisp::make-text-prop-interval
                     :start iv-s
                     :end start
                     :plist plist)
                    out))
            ;; Right piece (shifted left).
            (when (> iv-e end)
              (push (elisp::make-text-prop-interval
                     :start start
                     :end (- iv-e len)
                     :plist plist)
                    out))))))
      (nreverse out))))

(cl:defun text-properties-at (pos &optional object)
  "Bring-up subset of ELisp `text-properties-at'."
  (let ((obj (or object (current-buffer))))
    (cond
     ((stringp obj)
      (unless (and (integerp pos) (not (minusp pos)))
        (error "ELISP:TEXT-PROPERTIES-AT bad position: ~S" pos))
      (let ((len (length obj)))
        (when (> pos len)
          (error "ELISP:TEXT-PROPERTIES-AT out of range: ~S (len ~S)" pos len))
        (let ((intervals (elisp::%string-text-properties obj)))
          (when (null intervals)
            (return-from text-properties-at nil))
          (%intervals-properties-at pos intervals))))
     ((bufferp obj)
      (let* ((pos* (%pos pos))
             (pmax (1+ (length (elisp-buffer-text obj)))))
        (unless (and (integerp pos*) (plusp pos*))
          (error "ELISP:TEXT-PROPERTIES-AT bad position: ~S" pos))
        (when (> pos* pmax)
          (error "ELISP:TEXT-PROPERTIES-AT out of range: ~S (max ~S)" pos* pmax))
        (let ((intervals (%buffer-text-properties obj)))
          (when (null intervals)
            (return-from text-properties-at nil))
          (%intervals-properties-at pos* intervals))))
     (t
      (error "ELISP:TEXT-PROPERTIES-AT unsupported OBJECT: ~S" obj)))))

(cl:defun get-text-property (pos prop &optional object)
  "Bring-up subset of ELisp `get-text-property'."
  (plist-get (text-properties-at pos object) prop))

(cl:defun %text-props--normalize-pos (pos object caller)
  (cond
   ((stringp object)
    (unless (and (integerp pos) (<= 0 pos) (<= pos (length object)))
      (error "ELISP:~A bad position: ~S" caller pos))
    pos)
   ((bufferp object)
    (let* ((pos* (%pos pos))
           (pmax (1+ (length (elisp-buffer-text object)))))
      (unless (and (integerp pos*) (plusp pos*) (<= pos* pmax))
        (error "ELISP:~A bad position: ~S" caller pos))
      pos*))
   (t
    (error "ELISP:~A unsupported OBJECT: ~S" caller object))))

(cl:defun %text-props--max-pos (object)
  (cond
   ((stringp object) (length object))
   ((bufferp object) (1+ (length (elisp-buffer-text object))))
   (t (error "ELISP:TEXT-PROPS internal: unsupported OBJECT: ~S" object))))

(cl:defun %text-props--min-pos (object)
  (cond
   ((stringp object) 0)
   ((bufferp object) 1)
   (t (error "ELISP:TEXT-PROPS internal: unsupported OBJECT: ~S" object))))

(cl:defun text-property-any (start end prop value &optional object)
  "Bring-up subset of ELisp `text-property-any'."
  (let* ((obj (or object (current-buffer)))
         (s (%text-props--normalize-pos start obj "TEXT-PROPERTY-ANY"))
         (e (%text-props--normalize-pos end obj "TEXT-PROPERTY-ANY")))
    (when (> s e)
      (error "ELISP:TEXT-PROPERTY-ANY bad range: ~S..~S" start end))
    (when (= s e)
      (return-from text-property-any nil))
    (loop for i from s below e do
      (when (eq (get-text-property i prop obj) value)
        (return-from text-property-any i)))
    nil))

(cl:defun text-property-not-all (start end prop value &optional object)
  "Bring-up subset of ELisp `text-property-not-all'."
  (let* ((obj (or object (current-buffer)))
         (s (%text-props--normalize-pos start obj "TEXT-PROPERTY-NOT-ALL"))
         (e (%text-props--normalize-pos end obj "TEXT-PROPERTY-NOT-ALL")))
    (when (> s e)
      (error "ELISP:TEXT-PROPERTY-NOT-ALL bad range: ~S..~S" start end))
    (when (= s e)
      (return-from text-property-not-all nil))
    (loop for i from s below e do
      (unless (eq (get-text-property i prop obj) value)
        (return-from text-property-not-all i)))
    nil))

(cl:defun next-single-property-change (pos prop &optional object limit)
  "Bring-up subset of ELisp `next-single-property-change'."
  (let* ((obj (or object (current-buffer)))
         (p (%text-props--normalize-pos pos obj "NEXT-SINGLE-PROPERTY-CHANGE"))
         (lim (and limit (%text-props--normalize-pos limit obj "NEXT-SINGLE-PROPERTY-CHANGE")))
         (max (%text-props--max-pos obj))
         (scan-end (or lim max)))
    (when (and lim (= p lim))
      (return-from next-single-property-change p))
    (when (>= p scan-end)
      (return-from next-single-property-change nil))
    (let ((initial (get-text-property p prop obj)))
      (loop for i from (1+ p) below scan-end do
        (unless (eq (get-text-property i prop obj) initial)
          (return-from next-single-property-change i)))
      (if lim lim nil))))

(cl:defun previous-single-property-change (pos prop &optional object limit)
  "Bring-up subset of ELisp `previous-single-property-change'."
  (let* ((obj (or object (current-buffer)))
         (p (%text-props--normalize-pos pos obj "PREVIOUS-SINGLE-PROPERTY-CHANGE"))
         (lim (and limit (%text-props--normalize-pos limit obj "PREVIOUS-SINGLE-PROPERTY-CHANGE")))
         (min (%text-props--min-pos obj)))
    (when (and lim (= p lim))
      (return-from previous-single-property-change p))
    (when (<= p min)
      (return-from previous-single-property-change (and lim lim)))
    (let* ((ref (1- p))
           (scan-start (or lim min))
           (initial (get-text-property ref prop obj)))
      (loop for i from (1- ref) downto scan-start do
        (unless (eq (get-text-property i prop obj) initial)
          (return-from previous-single-property-change (1+ i))))
      (if lim lim nil))))

(cl:defun put-text-property (start end prop value &optional object)
  "Bring-up subset of ELisp `put-text-property'."
  (let ((obj (or object (current-buffer))))
    (cond
     ((stringp obj)
      (unless (and (integerp start) (integerp end) (<= 0 start) (<= start end))
        (error "ELISP:PUT-TEXT-PROPERTY bad range: ~S..~S" start end))
      (let ((len (length obj)))
        (when (> end len)
          (error "ELISP:PUT-TEXT-PROPERTY out of range: ~S..~S (len ~S)" start end len))
        (when (< start end)
          (let* ((old (or (elisp::%string-text-properties obj) nil))
                 (iv (elisp::make-text-prop-interval
                      :start start
                      :end end
                      :plist (list prop value))))
            (elisp::%set-string-text-properties obj (append old (list iv)))))))
     ((bufferp obj)
      (let* ((s (%pos start))
             (e (%pos end))
             (pmax (1+ (length (elisp-buffer-text obj)))))
        (unless (and (integerp s) (integerp e) (plusp s) (<= s e))
          (error "ELISP:PUT-TEXT-PROPERTY bad range: ~S..~S" start end))
        (when (> e pmax)
          (error "ELISP:PUT-TEXT-PROPERTY out of range: ~S..~S (max ~S)" s e pmax))
        (when (< s e)
          (let* ((old (or (%buffer-text-properties obj) nil))
                 (iv (elisp::make-text-prop-interval
                      :start s
                      :end e
                      :plist (list prop value))))
            (%set-buffer-text-properties obj (append old (list iv)))))))
     (t
      (error "ELISP:PUT-TEXT-PROPERTY unsupported OBJECT: ~S" obj))))
  t)

(cl:defun add-text-properties (start end props &optional object)
  "Bring-up subset of ELisp `add-text-properties'."
  (unless (and (listp props) (evenp (length props)))
    (error "ELISP:ADD-TEXT-PROPERTIES expects a plist, got: ~S" props))
  (loop for (k v) on props by #'cddr do
    (put-text-property start end k v object))
  t)

(cl:defun remove-text-properties (start end props &optional object)
  "Bring-up subset of ELisp `remove-text-properties'."
  (unless (and (listp props) (evenp (length props)))
    (error "ELISP:REMOVE-TEXT-PROPERTIES expects a plist, got: ~S" props))
  (loop for (k _v) on props by #'cddr do
    (put-text-property start end k nil object))
  t)

(cl:defun remove-list-of-text-properties (start end props &optional object)
  "Bring-up subset of ELisp `remove-list-of-text-properties'."
  (unless (listp props)
    (error "ELISP:REMOVE-LIST-OF-TEXT-PROPERTIES expects a list, got: ~S" props))
  (dolist (k props)
    (put-text-property start end k nil object))
  t)

(cl:defun set-text-properties (start end props &optional object)
  "Bring-up subset of ELisp `set-text-properties'."
  (unless (or (null props) (and (listp props) (evenp (length props))))
    (error "ELISP:SET-TEXT-PROPERTIES expects a plist or nil, got: ~S" props))
  (let ((obj (or object (current-buffer))))
    (cond
     ((stringp obj)
      (unless (and (integerp start) (integerp end) (<= 0 start) (<= start end))
        (error "ELISP:SET-TEXT-PROPERTIES bad range: ~S..~S" start end))
      (let ((len (length obj)))
        (when (> end len)
          (error "ELISP:SET-TEXT-PROPERTIES out of range: ~S..~S (len ~S)" start end len))
        (let* ((old (or (elisp::%string-text-properties obj) nil))
               (base (if old (%intervals-remove-range old start end) nil))
               (intervals (if (and props (< start end))
                              (append base
                                      (list (elisp::make-text-prop-interval
                                             :start start
                                             :end end
                                             :plist props)))
                              base)))
          (if intervals
              (elisp::%set-string-text-properties obj intervals)
              (elisp::%clear-string-text-properties obj)))))
     ((bufferp obj)
      (let* ((s (%pos start))
             (e (%pos end))
             (pmax (1+ (length (elisp-buffer-text obj)))))
        (unless (and (integerp s) (integerp e) (plusp s) (<= s e))
          (error "ELISP:SET-TEXT-PROPERTIES bad range: ~S..~S" start end))
        (when (> e pmax)
          (error "ELISP:SET-TEXT-PROPERTIES out of range: ~S..~S (max ~S)" s e pmax))
        (let* ((old (or (%buffer-text-properties obj) nil))
               (base (if old (%intervals-remove-range old s e) nil))
               (intervals (if (and props (< s e))
                              (append base
                                      (list (elisp::make-text-prop-interval
                                             :start s
                                             :end e
                                             :plist props)))
                              base)))
          (if intervals
              (%set-buffer-text-properties obj intervals)
              (%clear-buffer-text-properties obj)))))
     (t
      (error "ELISP:SET-TEXT-PROPERTIES unsupported OBJECT: ~S" obj))))
  t)

(cl:defun substring-no-properties (string &optional (from 0) to)
  "Bring-up subset of ELisp `substring-no-properties' (for strings)."
  (let ((s (substring string from to)))
    (elisp::%clear-string-text-properties s)
    s))

(cl:defun propertize (string &rest properties)
  "Bring-up subset of ELisp `propertize' (for strings)."
  (unless (stringp string)
    (error "ELISP:PROPERTIZE expects a string, got: ~S" string))
  (unless (evenp (length properties))
    (error "ELISP:PROPERTIZE expects a property list, got: ~S" properties))
  (let ((s (copy-seq string)))
    (elisp::%clear-string-text-properties s)
    (when properties
      (elisp::%set-string-text-properties
       s
       (list (elisp::make-text-prop-interval
              :start 0
              :end (length s)
              :plist properties))))
    s))

(cl:defun equal-including-properties (a b)
  "Bring-up subset of ELisp `equal-including-properties'."
  (cond
   ((and (stringp a) (stringp b))
    ;; `equal-including-properties' must compare string contents independent of
    ;; text properties, then compare properties at each position.
    (when (not (equal a b))
      (return-from equal-including-properties nil))
    (let ((len (length a)))
      (loop for i from 0 to len do
        (unless (%plist-equal-as-set (text-properties-at i a)
                                     (text-properties-at i b))
          (return-from equal-including-properties nil)))
      t))
   (t
    (equal a b))))

(cl:defun capitalize (s)
  "Bring-up subset of ELisp `capitalize'."
  (unless (stringp s)
    (error "ELISP:CAPITALIZE expects a string, got: ~S" s))
  (cond
   ((unibyte-string-p s)
    (let* ((cl-s (%elisp-string->cl-string s))
           (out (string-capitalize cl-s)))
      (string-to-unibyte out)))
   (t
    (string-capitalize s))))

(cl:defun substring (s from &optional to)
  "Bring-up subset of ELisp `substring' for strings.

Supports negative indices and TO = nil (meaning end of string)."
  (unless (stringp s)
    (error "ELISP:SUBSTRING expects a string, got: ~S" s))
  (unless (integerp from)
    (error "ELISP:SUBSTRING expects integer FROM, got: ~S" from))
  (let* ((n (length s))
         (start (if (minusp from) (+ n from) from))
         (end (cond
               ((null to) n)
               ((integerp to) (if (minusp to) (+ n to) to))
               (t (error "ELISP:SUBSTRING expects integer or nil TO, got: ~S" to)))))
    (when (or (< start 0) (> start n) (< end 0) (> end n) (< end start))
      (signal 'args-out-of-range (list s from to)))
    (let ((out (subseq s start end)))
      (let ((intervals (elisp::%string-text-properties s)))
        (when intervals
          (let ((out-intervals nil))
            (dolist (iv intervals)
              (let* ((iv-s (elisp::text-prop-interval-start iv))
                     (iv-e (elisp::text-prop-interval-end iv))
                     (s* (max start iv-s))
                     (e* (min end iv-e)))
                (when (< s* e*)
                  (push (elisp::make-text-prop-interval
                         :start (- s* start)
                         :end (- e* start)
                         :plist (elisp::text-prop-interval-plist iv))
                        out-intervals))))
            (when out-intervals
              (elisp::%set-string-text-properties out (nreverse out-intervals))))))
      out)))
