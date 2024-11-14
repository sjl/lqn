#-quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file quicklisp-init) (load quicklisp-init)))

(unless (find-package :lqn) (ql:quickload :lqn :silent t))
(in-package :lqn)

(defun cqn/read-from-file (f) (declare #.*opt*)
  (handler-case (csvloadf f)
    (error (e) (sh/exit-msg 55 "CSV: failed to READ file: ~a~%~%~a~&" f e))))
(defun cqn/read-from-pipe (&optional all) (declare #.*opt*)
  (handler-case (csvloads *standard-input* all)
    (end-of-file () nil)
    (error (e) (sh/exit-msg 55 "CSV: failed to PARSE from pipe:~%~%~a~&" e))))

(defun cqn/run-files (opts fx files) (declare #.*opt* (function fx))
  (loop for fn in files for fi from 0 do
    (sh/out :csv opts (sh/execute-qry fx (cqn/read-from-file fn) fn fi))))
(defun cqn/run-pipe (opts fx) (declare #.*opt* (function fx))
  (loop for csv = (cqn/read-from-pipe) for fi from 0 while csv
        do (sh/out :csv opts (sh/execute-qry fx csv ":pipe:" fi))))

; (require :sb-sprof)
; (sb-sprof:with-profiling (:max-samples 50000 :mode :cpu #|:time|# :report :graph)
(sh/run-from-shell (format nil
"██ cqn - CSV - LISP QUERY NOTATION (~a)

Usage:
  cqn [options] <qry> [files ...]
  cat sample.csv | cqn [options] <qry>

Options:
  -v prints the full compiled qry to stdout before the result
  -j output as JSON [default]
  -l output to readable lisp data (LDN)
  -t output as TXT
  -c output as CSV
  -m minified JSON. indented is default.
  -z preserve empty lines in TXT. [compct is default]
  -h show this message.

██ options can be write as -i -v or -iv.
██
██ when outputing in TXT, internal vectors or hts are printed in LDN
██ mode. use -tj and -tl to output to JSON or LDN respectively.
██ use -tjm to print a resulting vector as (minified) lines of json.
██
██ see docs at: https://github.com/inconvergent/lqn

Examples:
❭ cqn _ sample.csv                  # get everything in the file
❭ cqn '#{:k1 :k2}' sample.csv       # get k1, k2 from list of objects
❭ cqn '{:k1 :k2}' sample.csv        # get k1, k2 from object
❭ echo '{\"_id\": 1}' | cqn '{:_id}'   # query data from pipe
" (lqn:v?)) (cdr (cmd-args)) #'cqn/run-files #'cqn/run-pipe)
; )

