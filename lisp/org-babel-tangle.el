;;; org-babel-tangle.el --- Extract source code from org-mode files

;; Copyright (C) 2009 Dan Davison, Eric Schulte

;; Author: Dan Davison, Eric Schulte
;; Keywords: literate programming, reproducible research
;; Homepage: http://orgmode.org
;; Version: 0.01

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; Extract the code from source blocks out into raw source-code files.

;;; Code:
(require 'org-babel)

(defvar org-babel-tangle-langs nil
  "Association list matching source-block languages.  The car of
each element should be a string indicating the source block
language, and the cdr should be a list containing the extension
and shebang(#!) line to use when writing out the language to
file.")

(defun org-babel-load-file (file)
  "Load the contents of the Emacs Lisp source code blocks in the
org-mode formatted FILE.  This function will first export the
source code using `org-babel-tangle' and then load the resulting
file using `load-file'."
  (flet ((age (file)
              (time-to-seconds
               (time-subtract (current-time)
                              (sixth (file-attributes file))))))
    (let* ((base-name (file-name-sans-extension file))
           (exported-file (concat base-name ".el")))
      ;; (message "building %s" exported-file) ;; debugging
      ;; tangle if the org-mode file is newer than the elisp file
      (unless (and (file-exists-p exported-file) (> (age file) (age exported-file)))
        (org-babel-tangle-file file base-name "emacs-lisp"))
      (load-file exported-file)
      (message "loaded %s" exported-file))))

(defun org-babel-tangle-file (file &optional target-file lang)
  "Extract the bodies of all source code blocks in FILE with
`org-babel-tangle'.  Optional argument TARGET-FILE can be used to
specify a default export file for all source blocks.  Optional
argument LANG can be used to limit the exported source code
blocks by language."
  (save-window-excursion (find-file file) (org-babel-tangle target-file lang)))

(defun org-babel-tangle (&optional target-file lang)
  "Extract the bodies of all source code blocks from the current
file into their own source-specific files.  Optional argument
TARGET-FILE can be used to specify a default export file for all
source blocks.  Optional argument LANG can be used to limit the
exported source code blocks by language."
  (interactive)
  (save-excursion
    (let ((block-counter 0)
          path-collector)
      (mapc ;; for every language create a file
       (lambda (by-lang)
         (let* ((lang (car by-lang))
                (specs (cdr by-lang))
                (lang-f (intern (concat lang "-mode")))
                (lang-specs (cdr (assoc lang org-babel-tangle-langs)))
                (ext (first lang-specs))
                (she-bang (second lang-specs)))
           (mapc
            (lambda (spec)
              (let* ((tangle (cdr (assoc :tangle (third spec))))
                     (base-name (or (cond
                                     ((string= "yes" tangle)
                                      (file-name-sans-extension (buffer-file-name)))
                                     ((string= "no" tangle) nil)
                                     ((> (length tangle) 0) tangle))
                                    target-file))
                     (file-name (when base-name
                                  (concat base-name "." ext))))
                ;; ;; debugging
                ;; (message "tangle=%S base-name=%S file-name=%S"
                ;;          tangle base-name file-name)
                (when file-name
                  ;; delete any old versions of file
                  (when (and (file-exists-p file-name)
                             (not (member file-name path-collector)))
                    (delete-file file-name))
                  ;; drop source-block to file
                  (with-temp-buffer
                    (funcall lang-f)
                    (when she-bang (insert (concat she-bang "\n")))
                    (comment-region
                     (point) (progn (insert "generated by org-babel-tangle") (point)))
                    (org-babel-spec-to-string spec)
                    (append-to-file nil nil file-name))
                  ;; update counter
                  (setq block-counter (+ 1 block-counter))
                  (add-to-list 'path-collector file-name))))
            specs)))
       (org-babel-tangle-collect-blocks lang))
      (message "tangled %d source-code block%s" block-counter
               (if (> block-counter 1) "s" ""))
      path-collector)))

(defun org-babel-tangle-collect-blocks (&optional lang)
  "Collect all source blocks in the current org-mode file.
Return an association list of source-code block specifications of
the form used by `org-babel-spec-to-string' grouped by language.
Optional argument LANG can be used to limit the collected source
code blocks by language."
  (let ((block-counter 0) blocks)
    (org-babel-map-source-blocks (buffer-file-name)
      (setq block-counter (+ 1 block-counter))
      (let* ((link (progn (call-interactively 'org-store-link)
                          (org-babel-clean-text-properties (car (pop org-stored-links)))))
             (source-name (intern (or (org-babel-get-src-block-name)
                                      (format "block-%d" block-counter))))
             (info (org-babel-get-src-block-info))
             (src-lang (first info))
             (body (second info))
             (params (third info))
             (spec (list link source-name params body))
             by-lang)
        (unless (string= (cdr (assoc :tangle params)) "no") ;; maybe skip
          (unless (and lang (not (string= lang src-lang))) ;; maybe limit by language
            ;; add the spec for this block to blocks under it's language
            (setq by-lang (cdr (assoc src-lang blocks)))
            (setq blocks (delq (assoc src-lang blocks) blocks))
            (setq blocks (cons (cons src-lang (cons spec by-lang)) blocks))))))
    ;; blocks should contain all source-blocks organized by language
    ;; (message "blocks=%S" blocks) ;; debugging
    blocks))

(defun org-babel-spec-to-string (spec)
  "Insert the source-code specified by SPEC into the current
source code file.  This function uses `comment-region' which
assumes that the appropriate major-mode is set.  SPEC has the
form

  (link source-name params body)"
  (flet ((insert-comment (text)
                         (comment-region (point) (progn (insert text) (point)))))
    (let ((link (first spec))
          (source-name (second spec))
          (body (fourth spec)))
      (insert "\n\n")
      (insert-comment (format "[[%s][%s]]" (org-link-escape link) source-name))
      (insert (format "\n%s\n" (org-babel-chomp body)))
      (insert-comment (format "%s ends here" source-name))
      (insert "\n"))))

(provide 'org-babel-tangle)
;;; org-babel-tangle.el ends here
