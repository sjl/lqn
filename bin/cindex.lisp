(in-package :lqn)

(defvar *fragment-types*
  '(:/t/string :/t/keyword :/t/boolean :/t/fixnum :/t/float :/t/number
    :/t/cons :/t/character :/t/symbol :/t/comma :/t/unknown
    :/f/file :/f/filename :/f/top
    :/o/defun :/o/defmacro :/o/defvar :/o/let :/o/labels :/o/in-package
    :/o/declaim :/o/set-macro-character :/o/defpackage
    :/o/unknown))
(defun frag/get-type (co s)
  (frag/fnd co
    (typecase s (string :/t/string) (keyword :/t/keyword) (boolean :/t/boolean)
                (cons :/t/cons)     (symbol :/t/symbol)   (fixnum :/t/fixnum)
                (float :/t/float)   (number :/t/number)   (character :/t/character)
                (sb-impl::comma :/t/comma)
                (otherwise (warn "unexpected type: ~a" s) :/t/unknown))))

(defmacro code/qry (co &rest rest)
  `(auxin:with-struct (code- grp) ,co (grph:qry grp ,@rest)))

(defun allsym (o) (remove-duplicates (flatall* o 2)) )

(defun prt (o &optional s)
  (auxin:with-struct (code- i grp) o
    (format s "<@code (frags: ~a~%  ~a)>" i grp)))
(defstruct (code (:constructor -code ()) (:print-object prt))
  (frags (make-array 500000 :initial-element nil))
  (frag->ind (make-hash-table :test #'equalp))
  (grp (grph:make)) (i 0))

(defun code (&aux (co (-code)))
  (loop for o in *fragment-types* do (frag/reg co o)) co)

(defun frag/mget (co &rest rest) (apply #'sel* (code-frags co) rest))
(defun frag/get (co i)
  (declare (fixnum i))
  (auxin:with-struct (code- frags) co (aref frags i)))
(defun frag/fnd (co frag &optional (d :/o/unknown))
  (values (or (gethash frag (code-frag->ind co))
              (gethash d (code-frag->ind co)))))
(defun frag/reg (co frag)
  (labels ((reg (co frag)
             (auxin:with-struct (code- frag->ind i) co
               (setf (aref (code-frags co) i) frag)
               (incf (code-i co))
               (setf (gethash frag frag->ind) i)
               i)))
    (or (frag/fnd co frag nil) (reg co frag))))

(defun frag/lnk (co parent child prop)
  (declare (fixnum parent child))
  (auxin:with-struct (code- grp) co
    (grph:add*! grp parent child -> prop)
    (setf (code-grp co) grp)
    child))
(defun frag/attach (co parent frag prop)
  (declare (fixnum parent))
  (frag/lnk co parent (frag/reg co frag) prop))

(defun code/index (co fn)
  (auxin:with-struct (code- frag->ind) co
    (labels
      ((-link-obj-type (o oi)
         (typecase o
           (cons (let ((okv (psymb :keyword :/o/ (car o))))
                   (frag/lnk co (frag/fnd co okv) oi '(:obj))
                   (case okv ((:/o/defun :/o/defmacro :/o/defvar
                               :/o/in-package :/o/set-macro-character)
                              (frag/lnk co (frag/reg co (second o)) oi '(:name))))))))
       (-do-file-obj (o oi)
         (frag/lnk co (frag/fnd co :/f/file) oi '(:file))
         (frag/lnk co (frag/fnd co :/f/top) oi '(:file))
         (frag/lnk co (frag/get-type co o) oi '(:type))
         (-link-obj-type o oi)
         (loop for frag across (allsym o)
               do (frag/lnk co (frag/get-type co frag)
                                (frag/attach co oi frag '(:has))
                                '(:type)))))
      (loop with fni = (frag/attach co (frag/fnd co :/f/filename) fn '(:file))
            for o across (read-file-as-data-vector fn)
            do (-do-file-obj o (frag/attach co fni o '(:has)))))))

(defun code/write (co fn)
  (auxin:with-struct (code- grp i frag->ind frags) co
    (grph/io:gwrite fn grp :meta `((:frags . ,(head* frags i))
                                   (:frag->ind . ,(flatn$ frag->ind))))))
