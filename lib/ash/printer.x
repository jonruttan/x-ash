; # x-ash -- a POSIX shell on x-lang
;
; ## ash/printer.x -- how a shell shows a result
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A SHELL IS NOT A LISP, and this is where that shows.  What a shell prints is
; whatever the command printed, and the value of a command is its exit status
; -- which belongs nowhere near stdout.
;
; So this printer's job is mostly to be quiet.  A nil result prints nothing,
; and anything else is written.
;
; Symbols write bare: x's writer quotes them so an echo pastes back, so a token
; list would render as (('tok-word "a")) where the specs assert
; ((tok-word "a")).  Lang symbols-bare! sets that on the symbol type, for write
; and write-to-str alike.
(module ash/printer)
(import x/repl/lang)

(Lang symbols-bare!)

(def ash-repl-print
  (fn (_ result)
    (unless (null? result) (write result))
    (newline)))

(provide ash/printer ash-repl-print)
