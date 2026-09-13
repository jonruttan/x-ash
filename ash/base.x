; # x-ash -- a POSIX shell on x-lang
;
; ## ash/base.x -- the language, assembled
;
; @description A POSIX-ish shell: tokenizer, expansion, redirection,
;   pipelines, and the control structures, on x-lang's evaluator.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; No path literals and no dialect boot here: run.x owns both. This file must
; not re-include a platform module either -- on a booted tower that crashes
; rather than raising (x-lang#515).
;
; The shell tokenizes on its own base, isolated from the sexp reader so that
; `;` and `#` mean what a shell means by them; see ash/prims.x.

(import ash/prims)
(import ash/printer)

(provide ash/base ash-version sh-tokenize sh-eval %sh-status %ash-repl-print)

(def ash-version "0.1.0")

(include-once "./tokens.x")
(include-once "./eval.x")
