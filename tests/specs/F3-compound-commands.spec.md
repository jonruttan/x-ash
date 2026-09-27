## sh-eval compound commands in the cheapest forms

A compound command's own words -- `then`, `do`, `in`, `done`, `fi`, `esac` --
are read from the token list, and the cursor is written once for each: a
branch skipped, a clause that does not match and a `done` checked before the
loop goes round again write it not at all.  The evaluators use `match` and
the integer doors.

The first four cases are pins that hold on main too; their expectations match
`dash` and `/bin/sh`.  A `case` with nothing after it is a parse error, as any
other construct cut short is.  The costs are compared rather than counted.

### if, elif and else across lines

```sh
(do (sh-eval "( if false\nthen echo 1\nelif false; then echo 2\nelif true\nthen\n echo 3\nelse echo 4\nfi; if false; then :; fi; echo $? ) | tr '\\n' ','; echo") ())
```
---
    3,0,

### while, until, continue and break, two loops out too

```sh
(do (sh-eval "( i=0; while [ $i -lt 5 ]; do i=$((i+1)); [ $i = 2 ] && continue; [ $i = 4 ] && break; echo $i; done; until [ $i -ge 6 ]; do i=$((i+1)); done; echo $i; for a in 1 2 3; do for b in x y z; do [ $b = y ] && continue 2; [ $a = 3 ] && break 2; echo $a$b; done; done ) | tr '\\n' ','; echo") ())
```
---
    1,3,6,1x,2x,

### for over the parameters, over nothing, and over a split substitution

```sh
(do (sh-eval "( set -- p q; for x; do printf %s, $x; done; for x in; do echo no; done; for x in $(echo 1 2) \"3 4\"\ndo printf '[%s]' \"$x\"; done; echo )") ())
```
---
    p,q,[1][2][3 4]

### case: alternatives, an opening paren, a quoted paren, the default

```sh
(do (sh-eval "( for w in a b c zz '('; do case $w in (a) echo A;; b|c) echo BC;; \"(\") echo paren;; *) echo other;; esac; done; case x in a) echo no;; esac; echo $? ) | tr '\\n' ','; echo") ())
```
---
    A,BC,BC,other,paren,0,

### a case with nothing after it is a parse error

```sh
(do (sh-eval "{ ( eval 'case' ) 2>&1; echo $?; } | tr '\\n' ','; echo") ())
```
---
    ash: parse error: case without a word,2,

### four more case clauses cost less than twenty comparisons

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (ge5 (fn (_) (do (>= 5 1) (>= 5 1) (>= 5 1) (>= 5 1) (>= 5 1))))
      (run (fn (_ text)
             (let ((ts (first (%sh-mark-command (sh-tokenize text)))))
               (fn (_) (%eval-list (%mk-cursor ts)))))))
  (def five (run "case e in a) ;; b) ;; c) ;; d) ;; e) ;; esac"))
  (def one (run "case e in e) ;; esac"))
  (five)
  (one)
  (< (- (cost five) (cost one)) (cost (fn (_) (do (ge5) (ge5) (ge5) (ge5))))))
```
---
    #t

### four more times round a for loop cost less than twenty comparisons

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (ge5 (fn (_) (do (>= 5 1) (>= 5 1) (>= 5 1) (>= 5 1) (>= 5 1))))
      (run (fn (_ text)
             (let ((ts (first (%sh-mark-command (sh-tokenize text)))))
               (fn (_) (%eval-list (%mk-cursor ts)))))))
  (def five (run "for x in a b c d e; do done"))
  (def one (run "for x in a; do done"))
  (five)
  (one)
  (< (- (cost five) (cost one)) (cost (fn (_) (do (ge5) (ge5) (ge5) (ge5))))))
```
---
    #t
