; # x-ash -- a POSIX shell on x-lang
;
; ## run.x -- the entry point
;
; @description A POSIX-ish shell: its own tokenizer on its own base,
;   expansion, redirection, pipelines, control structures.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Usage:
;   x -l ash              interactive
;   x -l ash -f script.sh batch
;
; This file contains no path literals and no boot code. x.sh boots the dialect
; lang.xon declares, arms this bundle's root with import-path!, cats this file,
; and appends the launcher when no -f was given, so `import` below resolves
; against the bundle wherever it sits.
(import ash/base)
(import ash/repl)

(set! %lang-name "ASH Shell")
(set! %lang-version ash-version)
(set! %repl-prompt "$ ")
; A shell shows what the command printed; see ash/printer.x.
(set! %repl-print %ash-repl-print)

; THE LOOP IS OURS, not the launcher's, and it always was: a shell's unit is a
; line of shell, not an s-expression.  These four lines were the whole of the
; bundle's session handling, and prompt-and-print is the half that does not
; matter -- the platform loop's READ is the ambient sexp reader and its EVAL is
; eval!, so `x -l ash` answered "Unbound SYMBOL 'ls'" at a `$ ` prompt.  The
; specs never caught it because every one of them calls sh-eval directly;
; nothing in the suite started a session.  See ash/repl.x.
;
; Set as well as called: x.sh appends its own launcher (%banner then repl) when
; no file was named, and a bundle that only ever calls its loop leaves those two
; globals pointing at the sexp session for anything else that reaches them.
(set! %banner %ash-banner)
(set! repl %ash-repl)

; Batch (-f): stdin holds a shell script, not a session, and %ash-repl's fd-3
; swap would discard it unread. %batch? comes from the seam and means "a file
; was supplied". This line is last and nothing structural may follow it --
; neither branch returns.
;
; Not while this bundle is being imaged: the image writer loads this entry in a
; child to capture the booted lang, where %batch? is true and the child's stdin
; is the writer's own script, which %ash-batch would run and (Sys exit) out of
; the writer. %image-writing is bound in that child alone; a real boot raises
; Unbound and answers #f, so the guard chooses the session.
(if (guard (_ #f) %image-writing)
  ()
  (if %batch?
    (%ash-batch)
    (do (%ash-banner) (%ash-repl))))
