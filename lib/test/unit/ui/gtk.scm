(define-module test.unit.ui.gtk
  (extend test.unit.ui)
  (use test.unit)
  (use gauche.threads)
  (use gtk)
  (use gauche.vm.debugger)
  (use gauche.time)
  (use srfi-2)
  (export <test-ui-gtk>))
(select-module test.unit.ui.gtk)
(gtk-init (with-module user *argv*))

(define *timeout-time* 100)

(define-class <test-ui-gtk> ()
  ((main-window :accessor main-window-of)
   (load-library-name-entry :accessor load-library-name-entry-of)
   (load-button :accessor load-button-of)
   (suite-name-entry :accessor suite-name-entry-of)
   (run-button :accessor run-button-of)
   (progress-bar :accessor progress-bar-of)
   (test-count-label :accessor test-count-label-of)
   (assertion-count-label :accessor assertion-count-label-of)
   (success-count-label :accessor success-count-label-of)
   (failure-count-label :accessor failure-count-label-of)
   (error-count-label :accessor error-count-label-of)
   (list-window :accessor list-window-of)
   (fault-list :accessor fault-list-of)
   (fault-detail-list :accessor fault-detail-list-of)
   (detail-window :accessor detail-window-of)
   (outer-detail-sub-panel :accessor outer-detail-sub-panel-of)
   (fault-detail-label :accessor fault-detail-label-of)
   (status-entry :accessor status-entry-of))
  )

(define (make-main-window ui)
  (let ((window (gtk-window-new GTK_WINDOW_TOPLEVEL)))
    (g-signal-connect window "destroy"
                      (lambda _ (gtk-main-quit)))
    (gtk-widget-set-usize window 800 600)
    (gtk-window-set-policy window 1 1 0)
    (gtk-container-add window (make-main-panel ui))
    window))

(define (make-main-panel ui)
  (let ((panel (gtk-vbox-new #f 0)))
    (gtk-box-pack-start panel (make-load-panel ui) #f #f 0)
    (gtk-box-pack-start panel (make-suite-panel ui) #f #f 0)
    (gtk-box-pack-start panel (make-progress-panel ui) #f #f 0)
    (gtk-box-pack-start panel (make-info-panel ui) #f #f 0)
    (gtk-box-pack-start panel (make-list-panel ui) #f #f 0)
    (gtk-box-pack-start panel (make-detail-panel ui) #t #t 0)
    (gtk-box-pack-start panel (make-status-panel ui) #f #f 0)
    panel))

(define (make-load-panel ui)
  (let ((panel (gtk-hbox-new #f 10)))
    (gtk-container-set-border-width panel 10)
    (gtk-box-pack-start panel (gtk-label-new "Load:") #f #f 0)
    (gtk-box-pack-start panel (make-load-library-name-entry ui) #t #t 0)
    (gtk-box-pack-start panel (make-load-button ui) #f #f 0)
    panel))

(define (make-load-library-name-entry ui)
  (let ((entry (gtk-entry-new)))
    (gtk-entry-set-text entry (with-module user *program-name*))
    (slot-set! ui 'load-library-name-entry entry)
    entry))

(define (make-load-button ui)
  (let ((button (gtk-button-new-with-label "Load")))
    (slot-set! ui 'load-button button)
    (g-signal-connect button "clicked"
                      (lambda _
                        (reset-test-suites)
                        (load (gtk-entry-get-text
                               (load-library-name-entry-of ui)))
                        (output-status
                         ui
                         #`"Loaded ,(gtk-entry-get-text
                                      (load-library-name-entry-of ui))")
                        (gtk-widget-destroy (main-window-of ui))
                        (run-all-test :ui (make <test-ui-gtk>))))
    button))

(define (make-suite-panel ui)
  (let ((panel (gtk-hbox-new #f 10)))
    (gtk-container-set-border-width panel 10)
    (gtk-box-pack-start panel (gtk-label-new "Suite:") #f #f 0)
    (gtk-box-pack-start panel (make-suite-name-entry ui) #t #t 0)
    (gtk-box-pack-start panel (make-run-button ui) #f #f 0)
    panel))

(define (make-suite-name-entry ui)
  (let ((entry (gtk-entry-new)))
    (gtk-entry-set-editable entry #f)
    (slot-set! ui 'suite-name-entry entry)
    entry))

(define (make-run-button ui)
  (let ((button (gtk-button-new-with-label "Run")))
    (slot-set! ui 'run-button button)
    button))

(define (make-progress-panel ui)
  (let ((panel (gtk-hbox-new #f 10)))
    (gtk-container-set-border-width panel 10)
    (gtk-box-pack-start panel (make-test-progress-bar ui) #t #t 0)
    panel))

(define (make-test-progress-bar ui)
  (let ((bar (gtk-progress-bar-new)))
    (slot-set! ui 'progress-bar bar)
    (set-progress-bar-color! ui (make-green-color))
    bar))

(define (set-progress-bar-color! ui color)
  (gtk-timeout-add *timeout-time*
                   (lambda _
                     (gtk-widget-modify-bg (progress-bar-of ui)
                                           GTK_STATE_PRELIGHT
                                           color)
                     #f)))
  
(define (make-color r g b)
  (let ((color (make <gdk-color>)))
    (slot-set! color 'red r)
    (slot-set! color 'green g)
    (slot-set! color 'blue b)
    color))

(define (make-green-color)
  (make-color #x0000 #xffff #x0000))

(define (make-red-color)
  (make-color #xffff #x0000 #x0000))

(define (make-info-panel ui)
  (let ((panel (gtk-hbox-new #f 0)))
    (gtk-container-set-border-width panel 10)
    (gtk-box-pack-start panel (gtk-label-new "Tests:") #f #f 0)
    (gtk-box-pack-start panel (make-count-label ui "test") #t #f 0)
    (gtk-box-pack-start panel (gtk-label-new "Assertions:") #f #f 0)
    (gtk-box-pack-start panel (make-count-label ui "assertion") #t #f 0)
    (gtk-box-pack-start panel (gtk-label-new "Successes:") #f #f 0)
    (gtk-box-pack-start panel (make-count-label ui "success") #t #f 0)
    (gtk-box-pack-start panel (gtk-label-new "Failures:") #f #f 0)
    (gtk-box-pack-start panel (make-count-label ui "failure") #t #f 0)
    (gtk-box-pack-start panel (gtk-label-new "Errors:") #f #f 0)
    (gtk-box-pack-start panel (make-count-label ui "error") #t #f 0)
    panel))

(define (make-count-label ui type)
  (let ((label (gtk-label-new "0")))
    (slot-set! ui (string->symbol #`",|type|-count-label") label)
    (gtk-label-set-justify label GTK_JUSTIFY_LEFT)
    label))

(define (make-list-panel ui)
  (let ((panel (gtk-hbox-new #f 0)))
    (gtk-box-pack-start panel (make-list-scrolled-window ui) #t #t 0)
    panel))

(define (make-list-scrolled-window ui)
  (let ((window (gtk-scrolled-window-new #f #f)))
    (slot-set! ui 'list-window window)
    (gtk-scrolled-window-set-policy window
                                    GTK_POLICY_AUTOMATIC
                                    GTK_POLICY_AUTOMATIC)
    (gtk-widget-set-usize window -1 150)
    (gtk-scrolled-window-add-with-viewport window (make-fault-list ui))
    window))

(define (make-fault-list ui)
  (let ((list (gtk-list-new)))
    (slot-set! ui 'fault-list list)
    (slot-set! ui 'fault-detail-list '())
    (g-signal-connect list "select-child"
                      (lambda (lst item)
                        (show-fault ui
                                    (list-ref (fault-detail-list-of ui)
                                              (gtk-list-child-position lst item)))))
    (g-signal-connect list "unselect-child"
                      (lambda _
                        (clear-fault ui)))
    list))

(define (make-detail-panel ui)
  (let ((panel (gtk-hbox-new #f 0)))
    (gtk-box-pack-start panel (make-detail-scrolled-window ui) #t #t 0)
    panel))

(define (make-detail-scrolled-window ui)
  (let ((window (gtk-scrolled-window-new #f #f)))
    (slot-set! ui 'detail-window window)
    (gtk-scrolled-window-set-policy window
                                    GTK_POLICY_AUTOMATIC
                                    GTK_POLICY_AUTOMATIC)
    (gtk-widget-set-usize window 400 -1)
    (gtk-scrolled-window-add-with-viewport window
                                           (make-outer-detail-sub-panel ui))
    window))

(define (make-outer-detail-sub-panel ui)
  (let ((panel (gtk-hbox-new #f 0)))
    (slot-set! ui 'outer-detail-sub-panel panel)
    (gtk-box-pack-start panel (make-inner-detail-sub-panel ui) #f #f 0)
    panel))

(define (make-inner-detail-sub-panel ui)
  (let ((panel (gtk-hbox-new #f 0)))
    (gtk-box-pack-start panel (make-fault-detail-label ui) #f #f 0)
    panel))

(define (make-fault-detail-label ui)
  (let ((label (gtk-label-new "")))
    (slot-set! ui 'fault-detail-label label)
    (gtk-label-set-line-wrap label #f)
    label))

(define (show-fault ui message)
  (raw-show-fault ui message))

(define (clear-fault ui)
  (raw-show-fault ui ""))

(define (raw-show-fault ui message)
  (let ((label (fault-detail-label-of ui)))
    (gtk-label-set-text label message))
  (let ((panel (outer-detail-sub-panel-of ui)))
    panel))

(define (make-status-panel ui)
  (let ((panel (gtk-hbox-new #f 0)))
    (gtk-box-pack-start panel (make-status-entry ui) #t #t 0)
    panel))

(define (make-status-entry ui)
  (let ((entry (gtk-entry-new)))
    (slot-set! ui 'status-entry entry)
    (gtk-entry-set-editable entry #f)
    entry))

(define (error-line stack)
  (and-let* ((code (car stack))
             ((pair? code))
             (info (pair-attribute-get code 'source-info #f))
             ((pair? info))
             ((pair? (cdr info))))
            (format "~a:~a: ~s" (car info) (cadr info) code)))
  
(define (string-inc-as-number string . options)
  (let-optionals* options ((inc-value 1))
    (number->string (+ inc-value (string->number string)))))

(define (count-up-label label)
  (gtk-timeout-add *timeout-time*
                   (lambda _
                     (gtk-label-set-text label (string-inc-as-number 
                                                (gtk-label-get-text label)))
                     #f)))
  

(define-method test-successed ((self <test-ui-gtk>) test)
  (count-up-label (success-count-label-of self)))

(define-method test-failed ((self <test-ui-gtk>) test message stack-trace)
  (set-progress-bar-color! self (make-red-color))
  (count-up-label (failure-count-label-of self))
  (let ((fault-list (fault-list-of self))
        (fault-item (gtk-list-item-new-with-label
                     #`",(error-line (car stack-trace))\n,message in ,(name-of test)")))
    (gtk-widget-show fault-item)
    (append-fault-detail-list! self stack-trace)
    (gtk-list-append-items fault-list (list fault-item))))

(define-method test-errored ((self <test-ui-gtk>) test err)
  (set-progress-bar-color! self (make-red-color))
  (count-up-label (error-count-label-of self))
  (let ((stack-trace (cdr (vm-get-stack-trace))))
    (let ((fault-list (fault-list-of self))
          (fault-item (gtk-list-item-new-with-label
                       #`",(error-line (car stack-trace))\nError occured in ,(name-of test)")))
      (gtk-widget-show fault-item)
      (append-fault-detail-list! self stack-trace)
      (gtk-list-append-items fault-list (list fault-item)))))

(define (append-fault-detail-list! ui stack-trace)
  (slot-set! ui 'fault-detail-list
             (append (fault-detail-list-of ui)
                     (list
                      (call-with-output-string
                       (cut with-error-to-port <>
                            (lambda ()
                              (with-module gauche.vm.debugger
                                           (debug-print-stack
                                            stack-trace
                                            *stack-show-depth*)))))))))
  

(define-method test-run ((self <test-ui-gtk>) test test-thunk)
  (dynamic-wind
      (lambda () (output-status self #`"Running ,(name-of test)..."))
      test-thunk
      (lambda ()
        (count-up-label (test-count-label-of self))
        (gtk-timeout-add
         *timeout-time*
         (lambda _
           (let ((bar (progress-bar-of self)))
             (gtk-progress-set-value bar
                                     (+ 1 (gtk-progress-get-value bar))))
           (let ((label (assertion-count-label-of self)))
             (gtk-label-set-text label (string-inc-as-number
                                        (gtk-label-get-text label)
                                        (assertion-number-of test))))
           #f)))))

(define-method test-case-run ((self <test-ui-gtk>) test-case test-thunk)
  (test-thunk))

(define-method test-suite-run ((self <test-ui-gtk>) test-suite test-thunk)
  (let ((window (make-main-window self)))
    (slot-set! self 'main-window window)
     (gtk-window-set-title window (name-of test-suite))
     (reset-ui self test-suite)
     (g-signal-connect (run-button-of self) "clicked"
                       (lambda _ (rerun self test-suite test-thunk)))
     (gtk-widget-show-all window))
  (gtk-timeout-add *timeout-time* (lambda _ (run-test self test-thunk) #f))
  (gtk-main))

(define (rerun ui test-suite test-thunk)
  ;; (gtk-widget-activate (load-button-of ui))
  (soft-reset-test-suites (list test-suite))
  (reset-ui ui test-suite)
  (gtk-timeout-add 10 (lambda _ (run-test ui test-thunk) #f)))

(define (run-test ui test-thunk)
  (output-status ui "Started.")
  (let ((counter (make <real-time-counter>)))
    (with-time-counter counter (test-thunk))
    (output-status ui #`"Finished in ,(time-counter-value counter) seconds.")))

(define (output-status ui message)
;  (gtk-timeout-add *timeout-time*
;                   (lambda _
                     (gtk-entry-set-text (status-entry-of ui) message)
;                     #f))
                     )

(define (reset-ui ui suite)
  (gtk-entry-set-text (suite-name-entry-of ui) (name-of suite))
  (gtk-progress-configure (progress-bar-of ui) 0 0 (test-number-of suite))
  (slot-set! ui 'fault-detail-list '())
  (gtk-list-clear-items (fault-list-of ui) 0 -1)
  (set-progress-bar-color! ui (make-green-color))
  (for-each (lambda (label-accessor)
              (gtk-label-set-text (label-accessor ui) "0"))
            (list test-count-label-of
                  assertion-count-label-of
                  success-count-label-of
                  failure-count-label-of
                  error-count-label-of)))

(set-default-test-ui! (make <test-ui-gtk>))

(provide "test/unit/ui/gtk")