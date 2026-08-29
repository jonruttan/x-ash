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

(set! %lang-name "ASH Shell")
(set! %lang-version ash-version)
(set! %repl-prompt "$ ")
; A shell shows what the command printed; see ash/printer.x.
(set! %repl-print %ash-repl-print)
