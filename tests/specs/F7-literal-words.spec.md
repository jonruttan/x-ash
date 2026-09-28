## sh-eval a word that expands to itself

The walk that marks a complete command before it runs turns each bare word
that expands to itself into a tok-lit: no quote, no backslash, no `$` or
backquote, no glob character, no tilde and no `=`.  Its text is its one field,
taken with no expansion walk each time the command runs -- every time round a
loop, every call of a function.

The first case is a pin that holds on main too; its expectation matches
`dash` and `/bin/sh`.  The last counts the expansion walks a command makes.

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

### a constant word is not walked when its command runs

```sh
(let ((saved %sh-expand-str)
      (walks 0)
      (run (fn (_ text)
             (let ((ts (first (%sh-mark-command (sh-tokenize text)))))
               (fn (_) (%eval-list (%mk-cursor ts)))))))
  (def count
    (fn (_ text)
      (def thunk (run text))
      (set! walks 0)
      (set! %sh-expand-str
        (fn (_ s mode split? assign?)
          (set! walks (+ walks 1))
          (saved s mode split? assign?)))
      (guard (e (do (set! %sh-expand-str saved) (error e))) (thunk))
      (set! %sh-expand-str saved)
      walks))
  (list (count ": a b c") (count ": a $PWD c")))
```
---
    (0 1)
