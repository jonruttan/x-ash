; # x-ash -- a POSIX shell on x-lang
;
; ## run.x -- THE entry, and the only file here that may know a path
;
; @description A POSIX-ish shell on x-lang: its own tokenizer on its own
;   base, expansion, redirection, pipelines, control structures.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; Usage today (until `-l` grows a personality-root step, see README):
;   x.sh -F path/to/x-ash/run.x     interactive
;   x.sh -f path/to/x-ash/run.x     batch, program on stdin
;
; THE ONE FILE WITH LAYOUT KNOWLEDGE.  Every other file in this bundle
; resolves its siblings by `import`, so the bundle relocates.  That rule is
; the whole reason the last generation of personalities died -- see
; x-lang docs/personality-contract.md, "Why the last generation rotted".
; RADON, and this is the only one of the five that needs it.  ash forks,
; execs, dup2s and opens files -- Sys's process and file doors are radon
; opt-ins, exactly as the contract's worked example says of Logo.  personality
; .xon's (dialect rn) row is what turns a helium install into a legible refusal
; instead of an unbound symbol at the first pipeline.
(include "lib/x/boot/radon.x")

; --- Where this bundle lives ------------------------------------------------
; THE ENTRY CANNOT ASK.  x.sh CATS the entry into the engine's stdin rather
; than including it, so inside this file %include-curdir is "." and
; %install-root is unbound in a checkout.  An entry has no way to learn its
; own path -- which is why Logo's names its root with a literal and why the
; contract exempts entries from the path-literal lint.  Logo can get away
; with one literal because Logo lives INSIDE the platform tree; a bundle,
; by definition, does not.  That gap is the "searched personality root,
; extended by one step" the contract still lists as proposed.
;
; So: probe, and say so when nothing answers.  Every candidate below is a
; place a bundle actually sits today; the list shrinks to one line the day
; -l learns a personality root.
(def %ash-entry-candidates
  (list
    ; installed tree, or a checkout with apps/ash symlinked at the bundle
    (guard (_ "apps/ash") (%path-join %install-root "apps/ash"))
    ; checkout, cwd at the repo root -- what `x.sh -l ash` gives today
    "apps/ash"
    ; the entry was INCLUDED rather than piped (a harness, or `include`)
    (guard (_ ".") (%include-curdir))))
(def %ash-entry-find-root
  (fn (self roots)
    (if (null? roots)
      ()
      (if (Sys file-exists? (%path-join (first roots) "ash/base.x"))
        (first roots)
        (self (rest roots))))))
(def %ash-entry-bundle-root (%ash-entry-find-root %ash-entry-candidates))
(if (null? %ash-entry-bundle-root)
  (do
    ; Legible, not a bare "include: cannot open".  A refusal that names what
    ; it looked for is the difference between a five-minute fix and the
    ; afternoon the last generation of these cost.
    (display "x-ash: cannot find the bundle root -- no ash/base.x under:")
    (newline)
    (def %ash-entry-say
      (fn (self roots)
        (if (null? roots)
          ()
          (do
            (display "  ")
            (display (%path-join (first roots) "ash/base.x"))
            (newline)
            (self (rest roots))))))
    (%ash-entry-say %ash-entry-candidates)
    (display "Run from the x-lang repo root with apps/ash pointing here, or")
    (newline)
    (display "install the bundle under <install-root>/apps/ash.")
    (newline)
    (Sys exit 1))
  ())
(import-path! %ash-entry-bundle-root)

(import ash/base)

(set! %repl-prompt "$ ")
(set! %lang-name "ASH Shell")
(set! %lang-version ash-version)
; A shell prints what the command printed; see ash/printer.x.
(set! %repl-print %ash-entry-repl-print)

; Batch (-f) means stdin holds a shell script, not a session: the REPL's
; fd swap would discard it unread.  %batch? comes from x-core via banner.x.
(unless %batch? (do (%banner) (repl)))
