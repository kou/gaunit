(require 'cl)
(require 'compile)

(defvar run-test-suffixes '(".scm" ".rb" ".sh")
  "List of test file suffix.")

(defvar run-test-file-names '("test/run-test" "test/runner")
  "List of invoked file name by run-test.")

(defvar run-test-verbose-level-table '((0 . "-vs")
                                       (1 . "")
                                       (2 . "-vp")
                                       (3 . "-vn")
                                       (4 . "-vv"))
  "Passed argumets to run-test-file-names for set verbose level.")

(defvar run-test-mode-name "run-test"
  "Mode name of running test.")

(defconst run-test-error-regexp-alist-alist
  `((ruby-test-unit-failure
     "^test_.+(.+) \\(\\[\\(.+\\):\\([0-9]+\\)\\]\\):$" 2 3 nil nil 1)
    (ruby-test-unit
     "^ +\\[?\\(\\(.+\\):\\([0-9]+\\)\\(?::.+\\)?\\)\n" 2 3)
    ,@compilation-error-regexp-alist-alist)
  "Alist of values for `run-test-error-regexp-alist'.")

(defvar run-test-error-regexp-alist
  (mapcar 'car run-test-error-regexp-alist-alist)
  "Alist that specifies how to match errors in compiler output.")

(define-compilation-mode run-test-mode "run-test" "run-test-mode")


(defun run-test-buffer-name ()
  (concat "*" run-test-mode-name "*"))

(defun flatten (lst)
  (cond ((null lst) '())
        ((listp (car lst))
         (append (flatten (car lst))
                 (flatten (cdr lst))))
        (t (cons (car lst) (flatten (cdr lst))))))

(defun get-verbose-level-arg (num)
  (let ((elem (assoc num run-test-verbose-level-table)))
    (concat " "
            (if elem (cdr elem) ""))))

(defun find-run-test-file-in-directory (directory filenames)
  (do ((fnames filenames (cdr fnames))
       (fname (concat directory (car filenames))
              (concat directory (car fnames))))
      ((or (file-exists-p fname)
           (null fnames))
       (if (file-exists-p fname)
           fname
         nil))))

(defun find-run-test-file (filenames)
  (let ((init-dir "./"))
    (do ((dir init-dir (concat dir "../"))
         (run-test-file (find-run-test-file-in-directory init-dir filenames)
                        (find-run-test-file-in-directory dir filenames)))
        ((or run-test-file (string= "/" (expand-file-name dir)))
         run-test-file))))

(defun find-test-files ()
  (mapcar (lambda (run-test-file)
            (let ((test-file (find-run-test-file
                              (mapcar (lambda (suffix)
                                        (concat run-test-file suffix))
                                      run-test-suffixes))))
              (if test-file
                  (cons run-test-file test-file)
                test-file)))
          run-test-file-names))


(defun run-test-if-find (test-file-infos verbose-arg runner)
  (cond ((null test-file-infos) nil)
        ((car test-file-infos)
         (let ((test-file-info (car test-file-infos)))
           (let* ((run-test-file (car test-file-info))
                  (test-file (cdr test-file-info))
                  (name-of-mode "run-test")
                  (default-directory
                    (expand-file-name
                     (car (split-string test-file run-test-file)))))
             (save-excursion
               (save-some-buffers)
               (funcall runner
                        (concat (concat "./"
                                        (file-name-directory run-test-file))
                                (file-name-nondirectory test-file)
                                verbose-arg)))
             t)))
        (t (run-test-if-find (cdr test-file-infos) verbose-arg runner))))

(defun run-test (&optional arg)
  (interactive "P")
  (run-test-if-find (find-test-files)
                    (get-verbose-level-arg (prefix-numeric-value arg))
                    (lambda (command)
                      (compilation-start command 'run-test-mode))))

(defun run-test-in-new-frame (&optional arg)
  (interactive "P")
  (if (member (run-test-buffer-name)
              (mapcar 'buffer-name (buffer-list)))
      (kill-buffer (run-test-buffer-name)))
  (let ((current-frame (car (frame-list)))
        (target-directory (cadr (split-string (pwd))))
        (frame (make-frame)))
    (select-frame frame)
    (cd target-directory)
    (if (null (run-test arg))
        (delete-frame frame)
      (delete-window)
      (other-frame -1)
      (select-frame current-frame))))

(defun run-test-in-mini-buffer (&optional arg)
  (interactive "P")
  (run-test-if-find (find-test-files)
                    (get-verbose-level-arg (prefix-numeric-value arg))
                    (lambda (command)
                      (shell-command command))))

(provide 'run-test)
