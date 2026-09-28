## sh-eval an arithmetic expression is read once into a tree

An arithmetic expression is read once into a tree, and the tree is run each
time the expansion is.  A word's plan keeps the tree of an expression with
nothing to expand, so `$((i+1))` in the body of a loop is read once however
often the loop goes round.  What the read finds wrong -- a missing operand, a
`(` with no `)`, a digit its base does not have, text after the expression --
is a node of the tree where the read found it.  The tree runs its parts in the
order of their text, so an assignment ahead of the error is made and one after
it is not, and an error in a branch that is not taken is raised all the same.

The first three cases are pins that hold on main too.  The fourth counts the
reads a loop's arithmetic takes, and the last compares a cost.

### an assignment ahead of an error is made

```sh
(do (sh-eval "( x=0; trap 'echo \"x=$x\"' EXIT; : $(( (x=3) + (1 2) )) ) 2>&1 | tr '\\n' ','; echo") ())
```
---
    ash: arithmetic: syntax error in  (x=3) + (1 2) ,x=3,

### an error in a branch that is not taken is raised

```sh
(do (sh-eval "( x=0; trap 'echo \"x=$x\"' EXIT; : $(( 0 ? (2 + ) : (x=7) )) ) 2>&1 | tr '\\n' ','; ( x=0; trap 'echo \"x=$x\"' EXIT; : $(( (x=3) || (1 2) )) ) 2>&1 | tr '\\n' ','; echo") ())
```
---
    ash: arithmetic: syntax error in  0 ? (2 + ) : (x=7) ,x=0,ash: arithmetic: syntax error in  (x=3) || (1 2) ,x=3,

### a division by zero ahead of a syntax error is raised first

```sh
(do (sh-eval "( x=0; trap 'echo \"x=$x\"' EXIT; : $(( (x=5) + 1/0 + )) ) 2>&1 | tr '\\n' ','; echo") ())
```
---
    ash: arithmetic: division by 0,x=5,

### a loop's arithmetic is read once however often it goes round

The expression in `: $((f9_i*2+1))` is scanned as often going round three times
as going round once.

```sh
(let ((saved %sh-ar-skip-ws)
      (scans 0)
      (run (fn (_ text)
             (let ((ts (first (%sh-mark-command (sh-tokenize text)))))
               (fn (_) (%eval-list (%mk-cursor ts)))))))
  (def count
    (fn (_ text)
      (def thunk (run text))
      (set! scans 0)
      (set! %sh-ar-skip-ws
        (fn (_ s i n)
          (set! scans (+ scans 1))
          (saved s i n)))
      (guard (e (do (set! %sh-ar-skip-ws saved) (error e))) (thunk))
      (set! %sh-ar-skip-ws saved)
      scans))
  (= (count "for f9_i in 1; do : $((f9_i*2+1)); done")
     (count "for f9_i in 1 2 3; do : $((f9_i*2+1)); done")))
```
---
    #t

### expanding `$((i*2+1))` costs less than eight comparisons

The variables are restored afterwards, so `i` is set for this case alone.  The
token is expanded once before it is measured, so it holds its plan, as a word
in a loop's body does after the first time round.

```sh
(let ((saved %sh-vars)
      (cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (tok (first (sh-tokenize "$((i*2+1))"))))
  (%sh-var-set! "i" "5")
  (%sh-expand-tok tok ())
  (let ((got (< (cost (fn (_) (%sh-expand-tok tok ())))
                (cost (fn (_) ((fn (self k) (if (fx<? k 8) (do (>= k 3) (self (fx+ k 1))) ())) 0))))))
    (set! %sh-vars saved)
    got))
```
---
    #t
