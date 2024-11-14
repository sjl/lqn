(in-package :lqn)

(defun sh/one? (v) (if (= (length v) 1) (aref v 0) v))
(defun opt/verbose? (opts) (not (null (member :-v opts :test #'equal))))
(defun compile? (opts) (not (null (member :-c opts :test #'equal))))
(defun opt/help? (opts)    (member :-h opts :test #'equal))
(defun opt/indent? (opts)  (null (member :-m opts :test #'equal)))

(defun opt/all?    (opts) (member :-a opts :test #'eq))
(defun opt/nils?   (opts) (member :-z opts :test #'eq))
(defun opt/jsnopt? (opts) (member :-j opts :test #'eq))
(defun opt/csvopt? (opts) (member :-c opts :test #'eq))
(defun opt/ldnopt? (opts) (member :-l opts :test #'eq))
(defun opt/txtopt? (opts) (member :-t opts :test #'eq))
(defun opt/outfmt? (opts &optional (d :json))
  (cond ((opt/txtopt? opts) :txt) ((opt/ldnopt? opts) :ldn) ((opt/jsnopt? opts) :json) ((opt/csvopt? opts) :csv) (t d)))

(defmacro sh/exit-msg (i &rest rest) (declare (fixnum i))
  (declare (optimize speed))
  (if (< i 1) `(progn (format *standard-output* ,@rest) (terminate ,i t))
              `(progn (format *error-output* ,@rest) (terminate ,i t))))

(defun split-opts-args (args)
  (declare (optimize speed (safety 3)))
  (labels ((expl- (o) (loop for s across (subseq o 1) collect (kw (mkstr "-" s))))
           (explode- (opts) (loop for o in opts if (= (length o) 2) nconc `(,(kw o))
                                                else nconc (expl- o))))
   (loop named opts for k in args for i from 0
         if (pref? k "-") collect k into opts
         else do (return-from opts (values (explode- opts) (subseq args i)))
         finally (return-from opts (values (explode- opts) nil)))))

(defun sh/is-query (q ex) (or q (sh/exit-msg 5 "MISSING query!~%~%~a~&" ex)))
(defun sh/parse-query (q) (declare #.*opt*)
  (handler-case (let ((rd (read-all-str q)))
                 `(?pipe ,@(if rd rd '(nil))))
    (error (e) (sh/exit-msg 10 "failed to PARSE qry:~%~%~a~&" e))))

(defun sh/compile-query (qq) (declare #.*opt*)
  (handler-case (proc-qry qq)
    (error (e) (sh/exit-msg 20 "failed to COMPILE qry:~%~%~a~&" e))))
(defun sh/eval-query (cq) (declare #.*opt*)
  (handler-case (eval cq)
    (error (e) (sh/exit-msg 30 "failed to BUILD qry FX:~%~%~a~&" e))))

(defun sh/execute-qry (fx &rest rest) (declare #.*opt* (function fx))
  (handler-case (apply fx rest)
    (stream-error () (sh/exit-msg 0 ""))
    (error (e) (sh/exit-msg 80 "failed to EXECUTE qry:~%~%~a~&" e))))

(defun sh/run-from-shell (ex args filefx pipefx &optional no-data)
  (declare #.*opt* (simple-string ex) (function filefx pipefx))
  (multiple-value-bind (opts args) (split-opts-args args)
    (when (opt/help? opts) (sh/exit-msg 0 ex))
    (let* ((q     (sh/is-query (car args) ex)) (qq (sh/parse-query q))
           (cq    (sh/compile-query qq))       (fx (sh/eval-query cq))
           (files (cdr args)))
      (declare (function fx))
      (when (opt/verbose? opts) (qry/show qq cq))
      (cond (no-data (funcall pipefx opts fx))
            ((interactive-stream-p *standard-input*)
               (unless (< 0 (length files)) (sh/exit-msg 50 "MISSING files!~%~%~a~&" ex))
               (funcall filefx opts fx files))
            (t (funcall pipefx opts fx))))))

(defun sh/out (d opts res &optional (s *standard-output*) (zeros (opt/nils? opts)))
  (declare (optimize speed (safety 2)))
  (prtcomp
  (labels
    ((prtxt (res*) (format s "~&~a~%" res*))
     (prldn (res*) (handler-case (format s "~&~s~&" (ldnout res*))
                     (stream-error () (sh/exit-msg 0 ""))
                     (error (e) (sh/exit-msg 102 "LDN: failed to SERIALIZE:~%~%~a~&" e))))
     (prjsn (res*) (handler-case (jsnout res* :indent (opt/indent? opts) :s s)
                     (stream-error () (sh/exit-msg 0 ""))
                     (error (e) (sh/exit-msg 101 "JSON: failed to SERIALIZE:~%~%~a~&" e))))
     (prcsv (res*) (handler-case (csvout res* :s s)
                     (stream-error () (sh/exit-msg 0 ""))
                     (error (e) (sh/exit-msg 101 "CSV: failed to SERIALIZE:~%~%~a~&" e))))
     (dotxt (res*) (handler-case
                     (typecase res*
                        (string (doline res*))
                        (vector (loop for s across res*
                                  if (or zeros (smth? s t)) do (doline s)))
                        (otherwise (doline res*)))
                     (stream-error () (sh/exit-msg 0 ""))
                     (error (e) (sh/exit-msg 103 "TXT: failed to SERIALIZE:~%~%~a~&" e))))
     (doline (res*) (typecase res* (null nil)
                      (string     (prtxt res*)) (number (prtxt res*))
                      (vector     (if (opt/jsnopt? opts) (prjsn res*) (prldn res*)))
                      (hash-table (if (opt/jsnopt? opts) (prjsn res*) (prldn res*)))
                      (list       (prldn res*))
                      (otherwise  (prtxt res*)))))
   (ecase (opt/outfmt? opts d) (:json (prjsn res)) (:csv (prcsv res)) (:ldn (prldn res)) (:txt (dotxt res))))))

; TODO: auto split args, handle errors
(defun cmd (fx &rest args) (declare (string fx)) "run terminal command"
  (mvb (res err errcode) (uiop:run-program `(,fx ,@args) :output '(:string :stripped t))
    (values (splt res #.(str! #\Newline)) err errcode)))
; (defun now () (cmd "date" "+%Y%m%d-%H%M%S-%N"))
(defun now () "timestamp." (the string (aref (cmd "date" "+%Y-%m-%dT%H:%M:%S.%N") 0)))

; https://quickref.common-lisp.net/uiop.html#g_t_2768268_2769
; TODO: how are #P/strings handled here for input/output to other fxs?
(defun path? (path) "does this path exist?"
  (uiop:probe-file* (uiop:ensure-pathname path)))

(defun ls (&optional (pattern "*.*")) "list dir contents at this pattern." (uiop:directory* pattern))
(defun subdir (&optional (path (cwd))) "list subdirectories."
  (uiop:subdirectories (uiop:ensure-pathname path)))
(defun subfiles (&optional (path (cwd))) "list subdirectories."
  (uiop:directory-files (uiop:ensure-pathname path)))

(defun cwd () "current working dir." (uiop:getcwd))
(defun dir? (path) "does this dir exist?"
  (uiop:directory-exists-p (uiop:ensure-pathname path)))
(defun file? (path) "does this file exist?"
  (uiop:file-exists-p (uiop:ensure-pathname path)))
(defun cd (path) "change dir." (uiop:chdir path))

; TODO: some other functions?
; escape-shell-command (find-preferred-file) ensure-list

