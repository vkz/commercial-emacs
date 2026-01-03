(in-package #:clemacs)

(deftype emx-value ()
  '(unsigned-byte 64))

(defstruct (handle-table (:constructor make-handle-table (&key (start 1))))
  (next start :type emx-value)
  (free '() :type list)
  (map (make-hash-table :test 'eql)))

(defun handle-alloc (table value)
  (declare (type handle-table table))
  (let* ((free (handle-table-free table))
         (handle (if free
                     (pop free)
                     (prog1 (handle-table-next table)
                       (setf (handle-table-next table)
                             (1+ (handle-table-next table)))))))
    (setf (handle-table-free table) free)
    (setf (gethash handle (handle-table-map table)) value)
    handle))

(defun handle-get (table handle)
  (declare (type handle-table table))
  (check-type handle integer)
  (multiple-value-bind (value presentp) (gethash handle (handle-table-map table))
    (unless presentp
      (error "unknown handle: ~S" handle))
    value))

(defun handle-free (table handle)
  (declare (type handle-table table))
  (check-type handle integer)
  (when (nth-value 1 (gethash handle (handle-table-map table)))
    (remhash handle (handle-table-map table))
    (push handle (handle-table-free table))
    t))
