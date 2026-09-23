## sh-eval reading a number of fifteen digits or fewer

One digit loop reads every number the shell is handed as digits: an
arithmetic constant in each of its three bases, `[`'s integers, a positional
parameter's number, a descriptor, and an octal escape to `echo`.  Fifteen
digits or fewer stay inside a machine word in any of those bases, so they are
read on the integer doors; a longer run is read with the tower, which carries
it into a bignum when it has to.

Expectations match `/bin/sh` and `dash`.  The first three cases are pins that
hold on main too.  The cost is compared rather than counted, as spec 36
compares its tests, and read through a descriptor's number.

### fifteen digits and sixteen, in each base

```sh
(do (sh-eval "( echo $((999999999999999)) $((1000000000000000)) $((0xfffffffffffffff)) $((0x1000000000000000)) $((0777777777777777)) $((01000000000000000)) $((-9223372036854775807)) )") ())
```
---
    999999999999999 1000000000000000 1152921504606846975 1152921504606846976 35184372088831 35184372088832 -9223372036854775807

### the other readers

```sh
(do (sh-eval "( [ 1000000000000000 -gt 999999999999999 ] && echo gt; [ -0999 -eq -999 ] && echo eq; set -- a b c d e f g h i j; echo \"${10}\"; echo fd 3>&1 >&3; echo 'a\\0101\\060b' ) | tr '\\n' ','; echo") ())
```
---
    gt,eq,j,fd,aA0b,

### a digit the base does not have is refused past fifteen digits too

As in spec 31, the refusal is read through a command substitution: the
expansion fails in the child, so the value is empty.

```sh
(do (sh-eval "( v=$( printf '%s' \"$((08000000000000000))\" 2>/dev/null ); printf 'v=[%s]\\n' \"$v\" )") ())
```
---
    v=[]

### reading fifteen digits costs less than a tower multiply and add per digit

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) (%sh-digits-int "999999999999999")))
     (cost (fn (_) ((fn (self i) (if (fx<? i 15) (do (+ (* i 10) 1) (self (fx+ i 1))) ())) 0)))))
```
---
    #t
