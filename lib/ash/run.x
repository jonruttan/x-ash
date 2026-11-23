; # x-ash -- a POSIX shell on x-lang
;
; ## lib/ash/run.x -- the entry
;
; @description A POSIX-ish shell: its own tokenizer on its own base,
;   expansion, redirection, pipelines, control structures.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Usage:
;   x -l ash                          interactive
;   x -l ash -f script.sh             batch
;   x -l ash -- -c COMMAND [NAME [ARG...]]
;   x -l ash -- FILE [ARG...]
;   x -l ash -- -s [ARG...]           the script on stdin
;
; The module ash/run.  It holds no path literals and no boot code: x.sh boots
; the dialect bundle.xon declares, arms this bundle's lib/ with import-path!,
; imports this module and then calls its main, so `import` below resolves
; against the bundle wherever it sits.
(module ash/run)
(import ash/base ash-version)
(import ash/repl ash-repl ash-banner ash-main)
(import ash/printer ash-repl-print)
(import ash/eval sh-sweeps!)

(set! %lang-name "ASH Shell")
(set! %lang-version ash-version)
(set! %repl-prompt "$ ")
; A shell shows what the command printed; see ash/printer.x.
(set! %repl-print ash-repl-print)

; THE LOOP IS OURS, not the launcher's: a shell's unit is a line of shell, not
; an s-expression.  The platform loop's READ is the ambient sexp reader and its
; EVAL is eval!, so left to it `x -l ash` answers "Unbound SYMBOL 'ls'" at a
; `$ ` prompt.  The specs call sh-eval directly and start no session, so they
; would not catch that.  See ash/repl.x.
;
; Set as well as called: x.sh may append its own launcher (%banner then repl),
; and a bundle that only ever calls its loop leaves those two globals pointing
; at the sexp session for anything else that reaches them.
(set! %banner ash-banner)
(set! repl ash-repl)

; ash-main reads the shell's arguments and starts what they ask for (see
; ash/repl.x).  With none it is the session, or batch (-f): stdin holds a shell
; script, not a session, and ash-repl's fd-3 swap would discard it unread.
; %batch? comes from the seam and means "a file was supplied".  ash-main does
; not return.
;
; Not while this bundle is being imaged: the image writer boots this bundle in
; a child to capture it, where the child's stdin is the writer's own script,
; which ash-batch would run and (Sys exit) out of the writer.  %image-writing
; is bound in that child alone; a real boot raises Unbound and answers #f, so
; the guard chooses the session.
;
; A session or a script sweeps as it runs (%sh-sweeps? in ash/eval.x).  It is
; switched on here, past the image guard, so the image keeps it off and the
; suite, which never calls main, counts objects unswept.
(def main
  (fn (_)
    (if (guard (_ #f) %image-writing)
      ()
      (do
        (sh-sweeps! #t)
        (ash-main (guard (_ ()) (rest (Sys args (lit program)))))))))

(provide ash/run main)
