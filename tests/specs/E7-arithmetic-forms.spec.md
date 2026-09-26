## sh-eval arithmetic read in the cheapest forms

`$(( ))` is found and read every time its word is expanded, so the scan that
finds its end and the reader that evaluates it are written in the forms that
allocate least: `match` rather than `if`, `not`, `and` and `or`, a function's
bindings in its own body rather than inside a `do`, and the integer doors for
positions, characters and comparisons.  An operator is found through the group
of operators its first character starts, longest spelling first, and a name's
value and a decimal literal are read where they stand.

The first three cases are pins that hold on main too, and their expectations
match `/bin/sh` and `dash`.  The costs are compared rather than counted, as
spec 36 compares its tests.

### every comparison, at and around its edge

```sh
(do (sh-eval "( x=3; echo $((x < 3)) $((x < 4)) $((x <= 2)) $((x <= 3)) $((x > 3)) $((x > 2)) $((x >= 4)) $((x >= 3)) $((x == 3)) $((x != 3)) $((x != 2)) $((-1 > -2)) )") ())
```
---
    0 1 0 1 0 1 0 1 1 0 1 1

### the unary operators, parentheses and blanks

```sh
(do (sh-eval "( x=3; echo $((!x)) $((!0)) $((~x)) $((-x)) $((+x)) $(( (x) )) $((  ( ( x ) )  )) $((-+-x)) $((x*-1)) )") ())
```
---
    0 1 -4 -3 3 3 3 3 -3

### a variable's value, however it is written

```sh
(do (sh-eval "( a=12; b='  7 '; c=-3; d=+4; e=0x1f; f=010; h=; echo $((a+1)) $((b)) $((c)) $((d)) $((e)) $((f)) $((h+1)) $((nosuch+2)) )") ())
```
---
    13 7 -3 4 31 8 1 2

### every operator is found by its own spelling

Each entry of both operator tables is looked up at the start of its own name,
and the lookup answers that entry.

```sh
(let ((found? (fn (self groups entries)
                (match
                  ((null? entries) #t)
                  ((same? (%sh-ar-op-at (first (first entries)) 0
                                        (string-length (first (first entries))) groups)
                          (first entries))
                    (self groups (rest entries)))
                  (#t (first (first entries)))))))
  (list (found? %sh-ar-rank-groups %sh-ar-ranks)
        (found? %sh-ar-assign-groups %sh-ar-assign-ops)))
```
---
    (#t #t)

### the longest spelling is found, and nothing where none starts

```sh
(map (fn (_ t)
       (let ((e (%sh-ar-op-at t 0 (string-length t) %sh-ar-rank-groups)))
         (if (null? e) "none" (first e))))
     (list "||1" "|1" "&&1" "&1" "<<=" "<=1" "<1" ">>1" ">=1" "==1" "!=1" "=1" "!1" "?1"))
```
---
    ("||" "|" "&&" "&" "<<" "<=" "<" ">>" ">=" "==" "!=" "none" "none" "none")

### finding where `$((i+1))` ends costs less than one comparison

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) (%sh-cs-end "$((i+1))" 2 8 0))) (cost (fn (_) (>= 5 1)))))
```
---
    #t

### evaluating `i+1` costs less than eight comparisons

The variables are restored afterwards, so `i` is set for this case alone.

```sh
(let ((saved %sh-vars)
      (cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (%sh-var-set! "i" "5")
  (let ((got (< (cost (fn (_) (%sh-arith-eval "i+1")))
                (cost (fn (_) ((fn (self i) (if (fx<? i 8) (do (>= i 3) (self (fx+ i 1))) ())) 0))))))
    (set! %sh-vars saved)
    got))
```
---
    #t
