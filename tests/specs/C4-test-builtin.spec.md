## sh-eval the test builtin

`test` and `[` read their words by how many there are, and answer a string,
unary or numeric primary.  The numeric operands are the integers
`%sh-test-int` reads, never nil, and compare on the integer door, which takes
a bignum to its own comparison; a length is asked of the door too.  Each step
binds with `def`.

Expectations match `/bin/sh` and `dash`.  The first three cases are pins that
hold on main too.  The cost is compared rather than counted, as spec 36
compares its tests.

### every numeric operator, signs included

```sh
(do (sh-eval "( r=; for op in -eq -ne -lt -le -gt -ge; do for p in \"5 5\" \"5 20\" \"20 5\" \"-3 2\" \"+4 4\"; do set -- $p; if [ \"$1\" $op \"$2\" ]; then r=\"${r}1\"; else r=\"${r}0\"; fi; done; r=\"$r,\"; done; echo \"$r\" )") ())
```
---
    10001,01110,01010,11011,00100,10101,

### strings, lengths, negation, grouping and the connectives

```sh
(do (sh-eval "( [ x ] && echo a; [ \"\" ] || echo b; [ -n x ] && echo c; [ -n \"\" ] || echo d; [ -z \"\" ] && echo e; [ ! -n \"\" ] && echo f; [ a = a ] && echo g; [ a != b ] && echo h; [ \\( x \\) ] && echo i; [ x -a \"\" ] || echo j; [ x -o \"\" ] && echo k; [ ! x = y ] && echo l ) | tr '\\n' ','; echo") ())
```
---
    a,b,c,d,e,f,g,h,i,j,k,l,

### an operand that is no integer

```sh
(do (sh-eval "( [ x -lt 2 ] 2>/dev/null; echo \"s=$?\"; [ 5 -lt 2x ] 2>/dev/null; echo \"s=$?\"; [ 5 -lt \"\" ] 2>/dev/null; echo \"s=$?\"; [ \" 7\" -eq 7 ] && echo padded ) | tr '\\n' ','; echo") ())
```
---
    s=2,s=2,s=2,padded,

### asking `[ -n x ]` ten times costs less than twenty-five comparisons

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (w (list "-n" "x" "]")))
  (< (cost (fn (_) ((fn (self i) (if (fx<? i 10) (do (%sh-bracket w) (self (fx+ i 1))) ())) 0)))
     (cost (fn (_) ((fn (self i) (if (fx<? i 25) (do (>= i 3) (self (fx+ i 1))) ())) 0)))))
```
---
    #t
