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
; No path literals and no dialect boot here: run.x owns both.  The 2024
; ash-base.x opened by loading x-core AND lib/x/posix.x, both of which are the
; entry's business now -- and re-including a platform module on a booted tower
; is a segfault rather than an error (x-lang#515).
;
; THE ONLY NON-LISP OF THE FIVE, and the one whose 2024 architecture needed the
; least apology: a shell tokenizer on its OWN base, isolated from the sexp
; reader so `;` and `#` can mean what a shell means by them.  That design is
; still first-class -- see ash/prims.x.
;
; lib/parser.x is not here.  eval.x's own header says it "replaces parser.x +
; old eval.x", and nothing loaded parser.x in 2024 either; carrying 389 lines
; of superseded recursive descent into a new bundle would be carrying a fossil.

(import ash/prims)
(import ash/printer)

(provide ash/base ash-version sh-tokenize sh-eval %ash-repl-print)

(def ash-version "0.1.0")

(include-once "./tokens.x")
(include-once "./eval.x")
