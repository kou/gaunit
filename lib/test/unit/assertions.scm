(define-module test.unit.assertions
  (extend test.unit.common)
  (use srfi-1)
  (use test.unit.base)
  (use test.unit.run-context)
  (use gauche.parameter)
  (export define-assertion))
(select-module test.unit.assertions)

(define-class <assertion-failure> ()
  ((failure-message :accessor failure-message-of
                    :init-keyword :failure-message
                    :init-value "assertion failed")
   (actual :accessor actual-of
           :init-keyword :actual
           :init-value #f)))

(define (assertion-failure? obj)
  (is-a? obj <assertion-failure>))

(define (assertion-failure message . actual)
  (raise (apply make-assertion-failure message actual)))

(define (make-assertion-failure message . actual)
  (let ((failure (make <assertion-failure>
                   :failure-message
                   (apply handle-failure-message message actual))))
    (when (get-optional actual #f)
      (slot-set! failure 'actual (get-optional actual #f)))
    failure))

(define (handle-failure-message message . options)
  (let-optionals* options ((actual #f))
    (if (procedure? message)
        (message actual)
        message)))

(define (make-message-handler expected . keywords)
  (let-keywords* keywords ((after-expected "")
                           (after-actual ""))
    (lambda (actual)
      (format #f
              "expected: <~s>~a\n but was: <~s>~a"
              expected after-expected
              actual after-actual))))

(define (eval-body body-thunk)
  (call/cc
   (lambda (cont)
     (with-exception-handler
      cont
      (lambda ()
        (parameterize ((count-assertion #f))
          (body-thunk)))))))

(define-macro (define-assertion name&args . body)
  `(with-module test.unit.assertions
     (export ,(car name&args))
     (define ,name&args
       (if (test-run-context)
         (let ((result (eval-body (lambda () ,@body))))
           (if (count-assertion)
             (cond ((assertion-failure? result)
                    (run-context-failure (test-run-context)
                                         (current-test)
                                         (failure-message-of result)
                                         (car (retrieve-target-stack-trace))))
                   ((is-a? result <error>)
                    (run-context-error (test-run-context)
                                       (current-test)
                                       result))
                   (else
                    (run-context-pass-assertion (test-run-context)
                                                (current-test))))
             (if (or (assertion-failure? result)
                     (is-a? result <error>))
               (raise result))))))))

(define-assertion (fail . message)
  (raise (make <assertion-failure>
           :failure-message (get-optional message " Failure!"))))

(define-assertion (assert pred expected actual . message)
  (if (pred expected actual)
      #t
      (assertion-failure
       (get-optional message
                     (make-message-handler expected))
       actual)))

(define-assertion (assert-equal expected actual . message)
  (apply assert equal? expected actual message))

(define-assertion (assert-not-equal expected actual . message)
  (assert (lambda (x y)
            (not (equal? x y)))
          expected
          actual
          (get-optional message
                        (make-message-handler
                         expected
                         :after-expected " to not be equal?"))))

(define-assertion (assert-null actual . message)
  (if (null? actual)
      #t
      (assertion-failure
       (get-optional message
                     (make-message-handler '()))
       actual)))

(define-assertion (assert-not-null actual . message)
  (if (not (null? actual))
    #t
    (assertion-failure
     (get-optional message
                   (make-message-handler
                    '()
                    :after-expected " to not be ()"))
     actual)))

(define-assertion (assert-true actual . message)
  (apply assert eq? #t actual message))

(define-assertion (assert-false actual . message)
  (apply assert eq? #f actual message))

(define-assertion (assert-instance-of expected-class object . message)
  (if (is-a? object expected-class)
      #t
      (assertion-failure
       (get-optional
        message
        (format #f
                " expected:<~s> is an instance of <~s>\n  but was:<~s>"
                object expected-class (class-of object)))
       object)))

(define-assertion (assert-raise expected-class thunk . message)
  (assert-true (procedure? thunk)
               (format #f " <~s> must be procedure" thunk))
  (assert is-a? expected-class <class>
          " Should expect a class of exception")
  (call/cc
   (lambda (cont)
     (with-exception-handler
      (lambda (exn)
        (cont
         (if (is-a? exn expected-class)
             #t
             (make-assertion-failure
              (get-optional
               message
               (format #f
                       " expected:<~s> class exception\n  but was:<~s>"
                       expected-class
                       (class-of exn)))
              exn))))
      (lambda ()
        (thunk)
        (make-assertion-failure
         (get-optional
          message
          (format #f
                  " expected:<~s> class exception\n  but none was thrown"
                  expected-class))))))))

(define-assertion (assert-error thunk . message)
  (assert-true (procedure? thunk)
               (format #f " <~s> must be procedure" thunk))
  (with-error-handler
   (lambda (err) #t)
   (lambda ()
     (thunk)
     (assertion-failure
      (get-optional message " None expection was thrown")))))

(define-assertion (assert-error-message expected thunk . message)
  (assert-true (procedure? thunk)
               (format #f " <~s> must be procedure" thunk))
  (with-error-handler
   (lambda (err)
     (let* ((msg (ref err 'message))
            (ok? (if (regexp? expected)
                   (and (rxmatch expected msg) #t)
                   (string=? expected msg))))
       (or ok?
           (make-assertion-failure
            (get-optional message
                          (format #f
                                  " expected:<~s>~a\n  but was:<~s>"
                                  expected
                                  (if (regexp? expected)
                                    " is match"
                                    "")
                                  msg))
            msg))))
   (lambda ()
     (thunk)
     (assertion-failure
      (get-optional message " None expection was thrown")))))

(define-assertion (assert-not-raise thunk . message)
  (assert-true (procedure? thunk)
               (format #f " <~s> must be procedure" thunk))
  (call/cc
   (lambda (cont)
     (with-exception-handler
      (lambda (exn)
        (cont (make-assertion-failure
               (get-optional
                message
                (format #f
                        (string-append " expected no exception was thrown\n"
                                       "  but <~s> class exception was thrown")
                        (class-of exn)))
               exn)))
      (lambda ()
        (thunk) #t)))))

(define-assertion (assert-each assert-proc lst . keywords)
  (let-keywords* keywords ((apply-if-can #t)
                           (run-assert (lambda (assert-proc prepared-item)
                                         (if (and (list? prepared-item)
                                                  apply-if-can)
                                             (apply assert-proc prepared-item)
                                             (assert-proc prepared-item))))
                           (prepare (lambda (x) x)))
    (for-each (lambda (item)
                (call-with-values (lambda () (prepare item))
                  (lambda args
                    (apply run-assert assert-proc args))))
              lst)))

(define-assertion (assert-macro1 expanded form . message)
  (apply assert-equal expanded (macroexpand-1 form) message))

(define-assertion (assert-macro expanded form . message)
  (apply assert-equal expanded (macroexpand form) message))

(define-assertion (assert-lset-equal expected actual . message)
  (let ((result (lset= equal? expected actual)))
    (if result
      #t
      (assertion-failure
       (get-optional message
                     (make-message-handler
                      expected
                      :after-actual
                      (format #f
                              (string-append
                               "\n diff for expected<->actual:<~s>"
                               "\n diff for actual<->expected:<~s>")
                              (lset-difference equal? expected actual)
                              (lset-difference equal? actual expected))))
       actual))))

(define-assertion (assert-values-equal expected productor . message)
  (receive actual (productor)
    (apply assert equal? expected actual message)))

(define-assertion (assert-in-delta expected delta actual . message)
  (if (<= (- expected delta) actual (+ expected delta))
      #t
      (assertion-failure
       (get-optional
        message
        (make-message-handler expected
                              :after-expected (format #f " +/- <~s>" delta)))
       actual)))

(define-assertion (assert-output expected thunk . message)
  (let ((assert-proc (if (regexp? expected)
                       assert-match
                       assert-equal)))
    (apply assert-proc expected (with-output-to-string thunk) message)))

(define-assertion (assert-match expected actual . message)
  (if (regexp? expected)
    (if (rxmatch expected actual)
      #t
      (assertion-failure
       (get-optional message
                     (make-message-handler expected
                                           :after-expected " is matched"))
       actual))
    (assertion-failure
     (format #f "expected <~s> must be a regexp" expected))))

(provide "test/unit/assertions")
