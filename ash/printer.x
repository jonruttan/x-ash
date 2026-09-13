; # x-ash -- a POSIX shell on x-lang
;
; ## ash/printer.x -- how a shell shows a result
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A SHELL IS NOT A LISP, and this is where that shows.  The other four
; personalities re-mean `write` because Scheme and Kernel render symbols
; differently from x.  ash has no such quarrel: what a shell prints is whatever
; the command printed, and the value of a command is its exit status -- which
; belongs nowhere near stdout.
;
; So this printer's job is mostly to be quiet.  A nil result prints nothing, a
; status of 0 prints nothing, and anything else is displayed as-is.

(provide ash/printer %ash-repl-print %ash-write)

; ash needs its own `write`: x's is round-trippable, so a token list renders as
; (('tok-word "a")) where the specs assert ((tok-word "a")). Only the rendering
; of a token differs; everything else delegates to x's writer.
(def %ash-write ())
(def %x-write write)
(def %ash-write-items
  (fn (_ v)
    (%ash-write (first v))
    (if (null? (rest v))
      ()
      (if (pair? (rest v))
        (%seq (display " ") (%ash-write-items (rest v)))
        (%seq (display " . ") (%ash-write (rest v)))))))
(set! %ash-write
  (fn (_ v)
    (if (pair? v)
      (%seq (display "(") (%seq (%ash-write-items v) (display ")")))
      (if (symbol? v) (display v) (%x-write v)))))
(def write %ash-write)

(def %ash-repl-print
  (fn (_ result)
    (unless (null? result) (%ash-write result))
    (newline)))
