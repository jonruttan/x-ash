## sh-eval evaluating arithmetic

`$(( ))` is evaluated by one reader over the expression's text.  Its positions
and lengths step on the integer doors.  Each binary operator's entry carries
its function and, for `&&` and `||`, what the left side alone answers, so an
operator is applied without its name being looked up again.  A name is taken
as the target of an assignment only when an `=` stands within three
characters of the operator after it, since every assignment operator is one
to three characters ending in `=`.

Expectations match `/bin/sh` and `dash`.  The first four cases are pins that
hold on main too.  The cost is compared rather than counted, as spec 36
compares its tests.

### every binary operator, applied from its entry

```sh
(do (sh-eval "( a=5; echo $((a+1)) $((a-1)) $((a*2)) $((a/2)) $((a%2)) $((a<<1)) $((a>>1)) $((a&4)) $((a|2)) $((a^1)) $((a<6)) $((a>6)) $((a<=5)) $((a>=6)) $((a==5)) $((a!=5)) $((a&&0)) $((a||0)) )") ())
```
---
    6 4 10 2 1 10 2 4 7 4 1 0 1 0 1 0 0 1

### assignments, and the comparisons that only look like them

```sh
(do (sh-eval "( a=5; echo $((b = a + 1)) $b $((b += 2)) $((b <<= 1)) $((c=d=3)) $c $d $((a + b == 21)) $((a <= 5)) $((a != 5)) $((a>=5)) $((b>>=2)) $b )") ())
```
---
    6 6 8 16 3 3 3 1 1 0 1 4 4

### a variable's value, padded, signed or in another base

```sh
(do (sh-eval "( n='  7 '; m=-3; p=+4; q=0x10; r=010; echo $((n+1)) $((m*2)) $((p)) $((q)) $((r)) )") ())
```
---
    8 -6 4 16 8

### a command substitution that opens with a parenthesis

```sh
(do (sh-eval "( echo $( (echo sub) ) $((1+1)) $(( (2+3)*2 )) )") ())
```
---
    sub 2 10

### evaluating `i+1` costs less than twenty comparisons

The variables are restored afterwards, so `i` is set for this case alone.

```sh
(let ((saved %sh-vars)
      (cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (%sh-var-set! "i" "5")
  (let ((got (< (cost (fn (_) (%sh-arith-eval "i+1")))
                (cost (fn (_) ((fn (self i) (if (fx<? i 20) (do (>= i 3) (self (fx+ i 1))) ())) 0))))))
    (set! %sh-vars saved)
    got))
```
---
    #t
