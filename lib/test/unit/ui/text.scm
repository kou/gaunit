(define-module test.unit.ui.text
  (extend test.unit.ui)
  (use test.unit)
  (use gauche.vm.debugger)
  (use gauche.time)
  (use srfi-2)
  (export <test-ui-text>))
(select-module test.unit.ui.text)

(define-class <test-ui-text> ()
  ((successed :accessor successed-of)
   (verbose :accessor verbose-of :init-keyword :verbose
            :init-value :normal)))

(define *verbose-level* (make-hash-table 'eq?))

(hash-table-put! *verbose-level* :silent 0)
(hash-table-put! *verbose-level* :progress 1)
(hash-table-put! *verbose-level* :normal 2)
(hash-table-put! *verbose-level* :verbose 3)

(define (level>=? l1 l2)
  (>= (hash-table-get *verbose-level* l1)
      (hash-table-get *verbose-level* l2)))

(define-method display-when ((self <test-ui-text>) level message . options)
  (let-optionals* options ((print-proc display))
    (if (level>=? (verbose-of self) level)
        (print-proc message))))

(define (print-error-line stack)
  (and-let* ((code (car stack))
             ((pair? code))
             (info (pair-attribute-get code 'source-info #f))
             ((pair? info))
             ((pair? (cdr info))))
            (print (format "~a:~a: ~s" (car info) (cadr info) code))))
  
(define-method test-errored ((self <test-ui-text>) test err)
  (set! (successed-of self) #f)
  (display-when self :progress "E\n")
  (print-error-line (cadddr (vm-get-stack-trace)))
  (print #`"Error occured in ,(name-of test)")
  (with-error-to-port (current-output-port)
    (lambda ()
      (report-error err))))

(define-method test-successed ((self <test-ui-text>) test)
  #f)

(define-method test-failed ((self <test-ui-text>) test message stack-trace)
  (set! (successed-of self) #f)
  (display-when self :progress "F\n")
  (print-error-line (car stack-trace))
  (print message #`" in ,(name-of test)"))
;;   (with-error-to-port (current-output-port)
;;                       (lambda ()
;;                         (with-module gauche.vm.debugger
;;                                      (debug-print-stack
;;                                       stack-trace
;;                                       *stack-show-depth*)))))

(define-method test-start ((self <test-ui-text>) test)
  (set! (successed-of self) #t))

(define-method test-finish ((self <test-ui-text>) test)
  (if (successed-of self)
    (display-when self :progress ".")))

(define-method test-case-start ((self <test-ui-text>) test-case)
  (display-when self :verbose #`"-- Start test case ,(name-of test-case)\n"))

(define-method test-case-finish ((self <test-ui-text>) test-case)
  (display-when self :verbose #\newline))

(define-method test-suite-start ((self <test-ui-text>) test-suite)
  (display-when self :normal #`"- Start test suite ,(name-of test-suite)\n"))

(define-method test-suite-finish ((self <test-ui-text>) test-suite)
  (display-when self :normal "\n")
  (display-when
   self :normal
   (format "~s tests, ~s assertions, ~s successes, ~s failures, ~s errors"
           (test-number-of test-suite)
           (assertion-number-of test-suite)
           (success-number-of test-suite)
           (failure-number-of test-suite)
           (error-number-of test-suite))
   print)
  (display-when
   self :normal
   (format "Testing time: ~s" (operating-time-of test-suite)))
  (display-when self :progress "\n"))

(set-default-test-ui! (make <test-ui-text>))

(provide "test/unit/ui/text")
