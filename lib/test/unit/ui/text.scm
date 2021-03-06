(define-module test.unit.ui.text
  (extend test.unit.ui)
  (use test.unit)
  (use test.unit.color)
  (use test.unit.listener)
  (use test.unit.run-context)
  (use gauche.time)
  (use gauche.sequence)
  (use srfi-2)
  (use srfi-13)
  (export <test-ui-text>))
(select-module test.unit.ui.text)

(define pair-attribute-get (with-module gauche.internal pair-attribute-get))

(define *color-schemes*
  `((default
      (success . ,(make-color "green" :bold #t))
      (failure . ,(make-color "red" :bold #t))
      (pending . ,(make-color "magenta" :bold #t))
      (omission . ,(make-color "blue" :bold #t))
      (notification . ,(make-color "cyan" :bold #t))
      (error . ,(make-color "yellow" :bold #t)))))

(define (guess-color-availability)
  (cond ((not (sys-isatty (current-output-port))) #f)
        ((and-let* ((term (sys-getenv "TERM"))
                    ((or (#/term(?:-color)?$/ term)
                         (equal? term "screen")))))
         #t)
        ((equal? (sys-getenv "EMACS") "t") #t)
        (else #f)))

(define (guess-progress-row-max)
  (cond ((and-let* ((term-width (sys-getenv "TERM_WIDTH")))
           (string->number term-width)))
        ((not (sys-isatty (current-output-port))) -1)
        ((and-let* ((term (sys-getenv "TERM"))
                    ((or (#/term(?:-color)?$/ term)
                         (equal? term "screen")))))
         79)
        ((equal? (sys-getenv "EMACS") "t") -1)
        (else -1)))

(define-class <test-ui-text> (<test-ui-base>)
  ((verbose :accessor verbose-of :init-keyword :verbose
            :init-value 'normal)
   (faults :accessor faults-of :init-form '())
   (use-color :accessor use-color-of :init-keyword :use-color
              :init-thunk guess-color-availability)
   (color-scheme :accessor color-scheme-of
                 :init-form (cdr (assoc 'default *color-schemes*)))
   (reset-color :accessor reset-color-of
                :init-form (make-color "reset"))
   (progress-row :accessor progress-row-of :init-value 0)
   (progress-row-max :accessor progress-row-max-of
                     :init-thunk guess-progress-row-max)))

(define *verbose-level* (make-hash-table 'eq?))

(hash-table-put! *verbose-level* 'silent 0)
(hash-table-put! *verbose-level* 'progress 1)
(hash-table-put! *verbose-level* 'normal 2)
(hash-table-put! *verbose-level* 'verbose 3)

(define (level>=? l1 l2)
  (>= (hash-table-get *verbose-level* l1)
      (hash-table-get *verbose-level* l2)))

(define (level=? l1 l2)
  (= (hash-table-get *verbose-level* l1)
     (hash-table-get *verbose-level* l2)))

(define-method output ((self <test-ui-text>) message . options)
  (let-optionals* options ((color #f)
                           (level 'normal))
    (if (level>=? (verbose-of self) level)
      (let ((message (if (and (use-color-of self) color)
                       (string-append (escape-sequence-of color)
                                      message
                                      (escape-sequence-of (reset-color-of self)))
                       message)))
        (display message)
        (flush)))))

(define (output-progress self mark status)
  (output self mark (color self status) 'progress)
  (set! (progress-row-of self) (+ (progress-row-of self) (string-length mark)))
  (when (<= 0 (progress-row-max-of self) (progress-row-of self))
    (unless (level=? (verbose-of self) 'verbose)
      (output self "\n" #f 'progress))
    (set! (progress-row-of self) 0)))

(define (output-stack-trace self stack-trace)
  (let ((message (error-message #f stack-trace :max-depth 5)))
    (unless (string-null? message)
      (output self message)
      (output self "\n")))
  (and-let* ((line (error-line stack-trace)))
    (output self #`",|line|\n")))

(define (color self key)
  (cdr (assoc key (color-scheme-of self))))

(define-method test-listener-on-start ((self <test-ui-text>) run-context)
  #f)

(define-method test-listener-on-start-test-suite ((self <test-ui-text>)
                                                  run-context
                                                  test-suite)
  (output self #`"- (test suite) ,(name-of test-suite):\n" #f 'verbose))

(define-method test-listener-on-start-test-case ((self <test-ui-text>)
                                                 run-context
                                                 test-case)
  (output self #`"-- (test case) ,(name-of test-case):\n" #f 'verbose))

(define-method test-listener-on-start-test ((self <test-ui-text>)
                                            run-context
                                            test)
  (output self #`"--- (test) ,(name-of test): " #f 'verbose))

(define-method test-listener-on-success ((self <test-ui-text>) run-context test)
  (output-progress self "." 'success))

(define-method test-listener-on-pass-assertion ((self <test-ui-text>)
                                                run-context test)
  #f)

(define-method test-listener-on-pending ((self <test-ui-text>) run-context test
                                         message stack-trace)
  (output-progress self "P" 'pending)
  (push! (faults-of self)
         (list 'pending "Pending" test message stack-trace)))

(define-method test-listener-on-failure ((self <test-ui-text>) run-context test
                                         message stack-trace)
  (output-progress self "F" 'failure)
  (push! (faults-of self)
         (list 'failure "Failure" test message stack-trace)))

(define-method test-listener-on-error ((self <test-ui-text>)
                                       run-context test err stack-trace)
  (output-progress self "E" 'error)
  (push! (faults-of self)
         (list 'error "Error" test
               (error-message err stack-trace :max-depth 0)
               stack-trace)))

(define-method test-listener-on-finish-test ((self <test-ui-text>)
                                             run-context test)
  (output self "\n" #f 'verbose))

(define-method test-listener-on-finish-test-case ((self <test-ui-text>)
                                                  run-context
                                                  test-case)
  #f)

(define-method test-listener-on-finish-test-suite ((self <test-ui-text>)
                                                   run-context
                                                   test-suite)
  #f)

(define-method test-listener-on-finish ((self <test-ui-text>) run-context)
  (if (eq? 'verbose (verbose-of self))
    (unless (null? (faults-of self))
      (output self "\n"))
    (output self "\n\n"))
  (for-each-with-index
   (lambda (i args)
     (apply (lambda (i type label test message stack-trace)
              (output self (format "~3d) " (+ i 1)))
              (output self
                      (format "~a: ~a\n" label (name-of test))
                      (color self type))
              (output-stack-trace self stack-trace)
              (output self message)
              (output self "\n\n"))
            i
            args))
   (reverse (faults-of self)))
  (output self "\n" #f 'verbose)
  (output self (format "Finished in ~s seconds\n"
                       (elapsed-of run-context)))
  (output self "\n")
  (output self
          (format (string-append
                   "~s test(s), ~s assertion(s), ~s successe(s), ~s pending(s), "
                   "~s failure(s), ~s error(s)"
                   "\n"
                   "~s% passed")
                  (n-tests-of run-context)
                  (n-assertions-of run-context)
                  (n-successes-of run-context)
                  (n-pendings-of run-context)
                  (n-failures-of run-context)
                  (n-errors-of run-context)
                  (if (zero? (n-tests-of run-context))
                    0
                    (* 100.0
                       (/ (n-successes-of run-context)
                          (n-tests-of run-context)))))
          (color self (test-run-context-status run-context)))
  (output self "\n" #f 'progress))

(set-default-test-ui! (make <test-ui-text>))

(provide "test/unit/ui/text")
