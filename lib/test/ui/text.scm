(select-module test.unit)

(use gauche.vm.debugger)
(use gauche.time)
(use srfi-2)

(define-class <test-ui-text> ()
  ())

(define (print-error-line stack)
  (and-let* ((code (car stack))
             ((pair? code))
             (info (pair-attribute-get code 'source-info #f))
             ((pair? info))
             ((pair? (cdr info))))
            (print (format "~a:~a: ~s" (car info) (cadr info) code))))
  
(define-method test-errored ((self <test-ui-text>) test err)
  (print "E")
  (print-error-line (cadddr (vm-get-stack-trace)))
  (print #`"Error occured in ,(name-of test)")
  (with-error-to-port (current-output-port)
                      (lambda ()
                        (report-error err))))

(define-method test-successed ((self <test-ui-text>) test)
  (display "."))

(define-method test-failed ((self <test-ui-text>) test message stack-trace)
  (print "F")
  (print-error-line (car stack-trace))
  (print message #`" in ,(name-of test)")
  (with-error-to-port (current-output-port)
                      (lambda ()
                        (with-module gauche.vm.debugger
                                     (debug-print-stack
                                      stack-trace
                                      *stack-show-depth*)))))

(define-method test-run ((self <test-ui-text>) test test-thunk)
  (test-thunk))

(define-method test-case-run ((self <test-ui-text>) test-case test-thunk)
;  (print #`"-- Start test case ,(name-of test-case)")
  (test-thunk)
;  (newline)
  )

(define-method test-suite-run ((self <test-ui-text>) test-suite test-thunk)
  (let ((counter (make <real-time-counter>)))
;    (print #`"- Start test suite ,(name-of test-suite)")
    (with-time-counter counter (test-thunk))
    (newline)
    (print
     (format "~s tests, ~s assertions, ~s successes, ~s failures, ~s errors"
             (test-number-of test-suite)
             (assertion-number-of test-suite)
             (success-number-of test-suite)
             (failure-number-of test-suite)
             (error-number-of test-suite)))
    (print (format "Testing time: ~s" (time-counter-value counter)))))

(set-default-test-ui! (make <test-ui-text>))
