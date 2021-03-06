(define-module test.unit.assertions
  (extend test.unit.common)
  (use srfi-1)
  (use srfi-13)
  (use text.diff)
  (use slib)
  (use test.unit.base)
  (use test.unit.run-context)
  (use gauche.parameter)
  (use gauche.collection)
  (use gauche.test)
  (export define-assertion pretty-print-object))
(select-module test.unit.assertions)

(require 'pretty-print)

(define-class <assertion-failure> ()
  ((failure-message :accessor failure-message-of
                    :init-keyword :failure-message
                    :init-value "assertion failed")
   (actual :accessor actual-of
           :init-keyword :actual
           :init-value #f)
   (stack-trace :accessor stack-trace-of
                :init-keyword :stack-trace
                :init-form (retrieve-target-stack-trace))))

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

(define (pretty-print-object object)
  (let ((pretty-printed-object
         (string-trim-right (with-output-to-string
                              (lambda () (pretty-print object))))))
    (if (equal? pretty-printed-object "#[unknown]")
      (if (is-a? object <error>)
        (format #f
                "#<~a ~s>"
                (regexp-replace-all #/(^<|>$)/
                                    (x->string (class-name (class-of object)))
                                    "")
                (ref object 'message))
        (x->string object))
      pretty-printed-object)))

(define (format-diff from to)
  (string-trim-right (with-output-to-string (lambda () (diff-report from to)))))

(define (interested-diff? diff)
  (#/^(?:.*\n){2}/ diff))

(define (need-fold? diff)
  (#/^[-+].{79}/ diff))

(define (fold-string string)
  (string-join (map (lambda (line)
                      (regexp-replace-all #/(.{78})/ line "\\1\n"))
                    (string-split string "\n"))
               "\n"))

(define (format-folded-diff from to)
  (format-diff (fold-string from) (fold-string to)))

(define (append-diff-message output expected actual)
  (unless (string=? expected actual)
    (let ((diff (format-diff expected actual)))
      (if (interested-diff? diff)
        (format output
                (string-append
                 "\n"
                 "\n"
                 "diff:\n"
                 "~a")
                diff))
      (if (need-fold? diff)
        (format output
                (string-append
                 "\n"
                 "\n"
                 "folded diff:\n"
                 "~a")
                (format-folded-diff expected actual))))))

(define (make-message-handler expected . keywords)
  (let-keywords* keywords ((after-expected "")
                           (after-actual ""))
    (lambda (actual)
      (let ((pretty-printed-expected (pretty-print-object expected))
            (pretty-printed-actual (pretty-print-object actual)))
        (call-with-output-string
          (lambda (output)
            (format output
                    (string-append
                     "expected: <~a>~a\n"
                     " but was: <~a>~a")
                    pretty-printed-expected after-expected
                    pretty-printed-actual after-actual)
            (append-diff-message output
                                 pretty-printed-expected
                                 pretty-printed-actual)))))))

(define-method test-handle-exception ((test-case <test-case>) (test <test>)
                                      run-context (e <assertion-failure>))
  (test-run-context-failure run-context
                            test
                            (failure-message-of e)
                            (stack-trace-of e))
  #f)

(define-method test-handle-exception ((test <test>)
                                      run-context (e <assertion-failure>))
  (test-run-context-failure run-context
                            test
                            (failure-message-of e)
                            (stack-trace-of e))
  #f)

(define-macro (define-assertion name&args . body)
  `(begin
     (if (eq? 'test.unit.assertions (module-name (current-module)))
       (export ,(car name&args)))
     (define ,name&args
       (parameterize ((count-assertion #f))
         ,@body)
       (if (count-assertion)
         (test-run-context-pass-assertion (test-run-context)
                                          (current-test))))))

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
  (guard (e (else
             (unless (is-a? e expected-class)
               (assertion-failure
                (get-optional
                 message
                 (format #f
                         " expected:<~s> class exception\n  but was:<~s>"
                         expected-class
                         (class-of e)))
                e))))
         (thunk)
         (assertion-failure
          (get-optional
           message
           (format #f
                   " expected:<~s> class exception\n  but none was thrown"
                   expected-class)))))

(define-assertion (assert-error thunk . message)
  (assert-true (procedure? thunk)
               (format #f " <~s> must be procedure" thunk))
  (unless (guard (e (else #t))
                 (thunk)
                 #f)
    (assertion-failure
     (get-optional message " None expection was thrown"))))

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
  (guard (e (else (assertion-failure
                   (get-optional
                    message
                    (format #f
                            (string-append
                             " expected no exception was thrown\n"
                             "  but <~s> class exception was thrown")
                            (class-of e)))
                   e)))
         (thunk)))

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

(define-assertion (assert-macro expanded form . message)
  (apply assert-equal expanded (macroexpand form) message))

(define-assertion (assert-macro1 expanded form . message)
  (apply assert-equal expanded (macroexpand-1 form) message))

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

(define-assertion (assert-not-match expected actual . message)
  (if (regexp? expected)
    (if (rxmatch expected actual)
      (assertion-failure
       (get-optional message
                     (make-message-handler expected
                                           :after-expected " is not matched"))
       actual)
      #t)
    (assertion-failure
     (format #f "expected <~s> must be a regexp" expected))))

(define (collect-dangling-autoloads module)
  (filter (lambda (symbol)
            (guard (_ (else #t))
                   (global-variable-ref module symbol)
                   #f))
          (map (lambda (key&value)
                 (car key&value))
               (module-table module))))

(define (collect-nonexistent-exported-symbols module)
  (let ((exported-symbols (module-exports module)))
    (if (pair? exported-symbols)
      (filter (lambda (symbol)
                (guard (_ (else #t))
                       (global-variable-ref module symbol)
                       #f))
              exported-symbols)
      '())))

(define (toplevel-closures module)
  (filter closure?
          (map (lambda (sym)
                 (guard (_ (else #f))
                        (global-variable-ref module sym #f)))
               (hash-table-keys (module-table module)))))
(define closure-grefs (with-module gauche.test closure-grefs))
(define dangling-gref? (with-module gauche.test dangling-gref?))

(define (collect-unresolvable-references module)
  (fold (lambda (closure previous)
          (append (filter (lambda (x) x)
                          (map (lambda (gref)
                                 (dangling-gref? gref closure))
                               (closure-grefs closure)))
                  previous))
        '()
        (toplevel-closures module)))

(define-assertion (assert-valid-module module-or-name . message)
  (let ((module (if (module? module-or-name)
                  module-or-name
                  (find-module module-or-name))))
    (unless module
      (assertion-failure
       (format #f "expected: <~s> is existent module" module-or-name)))
    (let* ((nonexistent-exported-modules
            (collect-nonexistent-exported-symbols module))
           (dangling-autoloads
            (lset-difference eq?
                             (collect-dangling-autoloads module)
                             nonexistent-exported-modules))
           (unresolvable-references
            (collect-unresolvable-references module))
           (message (call-with-output-string
                      (lambda (output)
                        (unless (null? dangling-autoloads)
                          (format output
                                  "unautoloadable symbols: <~a>\n"
                                  (pretty-print-object dangling-autoloads)))
                        (unless (null? nonexistent-exported-modules)
                          (format output
                                  "nonexistent exported symbols: <~a>\n"
                                  (pretty-print-object
                                   nonexistent-exported-modules)))
                        (unless (null? unresolvable-references)
                          (format output
                                  "unresolvable references: <~a>\n"
                                  (pretty-print-object
                                   (map (lambda (gref)
                                          (format #f "~a(~a)"
                                                  (car gref) (cdr gref)))
                                        unresolvable-references))))))))
      (unless (equal? "" message)
        (assertion-failure
         (format #f "<~s> isn't valid module\n~a"
                 module (string-trim-right message)))))
    #t))

;;; FIXME
(define-assertion (assert-predicate predicate arguments . message)
  (let ((actual (apply predicate arguments)))
    (if actual
      #t
      (assertion-failure
       (get-optional message
                     (make-message-handler `(,predicate ,@arguments)))
       actual))))

;;; FIXME
(define-assertion (assert-not-predicate predicate arguments . message)
  (let ((actual (apply predicate arguments)))
    (if actual
      (assertion-failure
       (get-optional message
                     (make-message-handler `(,predicate ,@arguments)))
       actual)
      #t)))

;;; FIXME
(export assert-predicate*)
(define-macro (assert-predicate* predicate-form . message)
  `(assert-predicate ,(car predicate-form)
                     (list ,@(cdr predicate-form))
                     (format #f "<~s> should #t" ',predicate-form)))

;;; FIXME
(export assert-not-predicate*)
(define-macro (assert-not-predicate* predicate-form . message)
  `(assert-not-predicate ,(car predicate-form)
                         (list ,@(cdr predicate-form))
                         (format #f "<~s> should #f" ',predicate-form)))

(provide "test/unit/assertions")
