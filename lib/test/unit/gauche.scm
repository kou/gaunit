(define-module test.unit.gauche
  (use srfi-1)
  (use srfi-37)
  (use test.unit.auto-runner)
  (use test.unit.base)
  (export main))
(select-module test.unit.gauche)

(define (top-level-form? sexp)
  (and (list? sexp)
       (memq (car sexp)
             '(define use define-class define-module define-recode-type
                define-condition-type define-reader-ctor define-values
                define-macro define-syntax define-constant))))

(define (load-gauche-test-file file)
  (let ((test-module-name #f)
        (sexp-list (call-with-input-file file
                     (lambda (input)
                       (port->sexp-list input)))))
    (for-each (lambda (expression)
                (cond ((equal? '(use gauche.test) expression) #f)
                      ((and (list? expression)
                            (eq? 'test-start (car expression)))
                       (set! test-module-name (cadr expression)))))
              sexp-list)
    (when test-module-name
      (let* ((test-module (make-module (string->symbol test-module-name)))
             (test-case-name (cadar
                              (filter (lambda (sexp)
                                        (and (list? sexp)
                                             (equal? (car sexp) 'test-start)))
                                      sexp-list)))
             (test-case (make <test-case> :name test-case-name)))
        (eval '(extend test.unit.test-case)
              test-module)
        (eval '(use test.unit.gauche-compatible)
              test-module)
        (eval `(begin
                 ,@(filter top-level-form? sexp-list))
              test-module)
        (push! (tests-of test-case)
               (make <test>
                 :name "gauche.test test"
                 :test (eval `(lambda ()
                                ,@(remove (lambda (sexp)
                                            (or (equal? sexp '(use gauche.test))
                                                (top-level-form? sexp)))
                                          sexp-list))
                             test-module)))
        (test-suite-add-test-case! (gaunit-default-test-suite)
                                   test-case)))))

(define auto-runner-main main)
(define (main args)
  (receive (options files)
    (args-fold (cdr args)
      '()
      (lambda (option name arg options files)
        (if (or (char? name) (eq? arg #f))
          (values (append options (list #`"-,name")) files)
          (values (append options (list #`"--,name" arg)) files)))
      (lambda (operand options files)
        (values options (cons operand files)))
      '()
      '())
    (for-each load-gauche-test-file files)
    (auto-runner-main (cons (car args) options))))

(provide "test/unit/gauche")
