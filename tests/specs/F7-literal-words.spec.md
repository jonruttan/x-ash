## sh-eval a word that expands to itself

The walk that marks a complete command before it runs turns each bare word
that expands to itself into a tok-lit: no quote, no backslash, no `$` or
backquote, no glob character, no tilde and no `=`.  Its text is its one field,
taken as it is each time the command runs -- every time round a loop, every
call of a function -- with no plan read for it or run.

The first case is a pin that holds on main too; its expectation matches
`dash` and `/bin/sh`.  The last counts the words a command reads into plans.

### constant words among the others, in each place a word stands

```sh
(do (sh-eval "( x=abc; echo lit $x \"$x\" 'q' c=1 -n; for w in p q; do printf %s, $w; done; echo; case lit in lit) echo matched;; esac; export e=1 f; echo $e; g() { echo in-g; }; g ) | tr '\\n' ','; echo") ())
```
---
    lit abc abc q c=1 -n,p,q,,matched,1,in-g,

### the walk makes a tok-lit of a word that expands to itself

```sh
(write (first (%sh-mark-command (sh-tokenize "echo a$x 'b' c=1 ~ *.c d"))))
```
---
    ((tok-lit "echo") (tok-word "a$x") (tok-sq "b") (tok-word "c=1") (tok-word "~") (tok-word "*.c") (tok-lit "d"))

### a constant word is never read into a plan

```sh
(let ((saved %sh-word-plan)
      (reads 0)
      (run (fn (_ text)
             (let ((ts (first (%sh-mark-command (sh-tokenize text)))))
               (fn (_) (%eval-list (%mk-cursor ts)))))))
  (def count
    (fn (_ text)
      (def thunk (run text))
      (set! reads 0)
      (set! %sh-word-plan
        (fn (_ s n mode assign?)
          (set! reads (+ reads 1))
          (saved s n mode assign?)))
      (guard (e (do (set! %sh-word-plan saved) (error e))) (thunk))
      (set! %sh-word-plan saved)
      reads))
  (list (count ": a b c") (count ": a $PWD c")))
```
---
    (0 1)
