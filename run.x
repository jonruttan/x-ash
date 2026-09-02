; # x-ash -- a POSIX shell on x-lang
;
; ## run.x -- THE entry
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
; THIS FILE KNOWS NO PATHS, and that is the whole point of the arrangement.
; x.sh boots the dialect lang.xon declares, arms this bundle's root with
; import-path!, cats this file, and appends the launcher when no -f was given.
; So by the time anything below runs, the platform is up and `import` resolves
; against the bundle wherever it happens to sit.
;
; It used to do all of that itself: include "lib/x-core.x" to self-boot, probe
; a list of candidate directories to guess its own location, and end with its
; own %batch?-guarded launcher.  Every line of that was a workaround for `-l`
; not knowing about bundles.  It does now.
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
; swap would discard it unread.  %batch? comes from the seam and means "a file
; was supplied".  This line is LAST and nothing structural may follow it --
; neither branch returns.
(if %batch?
  (%ash-batch)
  (do (%ash-banner) (%ash-repl)))
