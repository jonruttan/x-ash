## sh-eval arithmetic precedence

Each binary operator has a rank: its level's place in the precedence table,
counted from the loosest.  Reading the right operand of an operator, the
reader takes in only operators ranked above that one, so a tighter operator
binds into the operand and an equal one is left for the reader outside it --
which is what makes every level group to the left.

The operator after an operand is read once for each operand still waiting on
it, not once for every level of the table, so a chain of the loosest operator
costs no more to read than a chain of the tightest.

Expectations match `dash`.  bash agrees on every value but the two whose
skipped operand divides by zero, which it evaluates anyway.

### a tighter operator between two looser ones

```sh
(do (sh-eval "printf '%s\\n' \"$((1+2*3+4))\"") ())
```
---
    11

### operators of one level group to the left

```sh
(do (sh-eval "printf '%s\\n' \"$((1+10-2-3))\"") ())
```
---
    6

### `&&` binds tighter than `||` on its right

```sh
(do (sh-eval "printf '%s\\n' \"$((1||0&&0))\"") ())
```
---
    1

### and on its left

```sh
(do (sh-eval "printf '%s\\n' \"$((0&&1||1))\"") ())
```
---
    1

### products inside a chain of sums and differences

```sh
(do (sh-eval "printf '%s\\n' \"$((2*3+4*5-6/2))\"") ())
```
---
    23

### divisions group to the left ahead of a sum

```sh
(do (sh-eval "printf '%s\\n' \"$((100/10/5+1))\"") ())
```
---
    3

### shifts group to the left

```sh
(do (sh-eval "printf '%s\\n' \"$((1<<2<<3))\"") ())
```
---
    32

### a comparison's answer is an operand of the next comparison

```sh
(do (sh-eval "printf '%s\\n' \"$((1<2<3))\"") ())
```
---
    1

### so `3>2>1` is false

```sh
(do (sh-eval "printf '%s\\n' \"$((3>2>1))\"") ())
```
---
    0

### four levels in one expression

```sh
(do (sh-eval "printf '%s\\n' \"$((1+1==2&&3>2))\"") ())
```
---
    1

### unary minus on both operands of a product

```sh
(do (sh-eval "printf '%s\\n' \"$((-2*-3+1))\"") ())
```
---
    7

### `!` takes only its own operand

```sh
(do (sh-eval "printf '%s\\n' \"$((!0+1))\"") ())
```
---
    2

### and so does `~`

```sh
(do (sh-eval "printf '%s\\n' \"$((~1+1))\"") ())
```
---
    -1

### a product inside a chain of differences

```sh
(do (sh-eval "printf '%s\\n' \"$((10-2*3-1))\"") ())
```
---
    3

### the three bitwise levels together

```sh
(do (sh-eval "printf '%s\\n' \"$((5&3|8^2))\"") ())
```
---
    11

### a parenthesised conditional as an operand

```sh
(do (sh-eval "printf '%s\\n' \"$((1+(2*3>5?10:20)*2))\"") ())
```
---
    21

### nested parentheses

```sh
(do (sh-eval "printf '%s\\n' \"$((((((1+2))))*3))\"") ())
```
---
    9

### spaces around every operator

```sh
(do (sh-eval "printf '%s\\n' \"$(( 1 + 2 * 3 ))\"") ())
```
---
    7

### parentheses on both sides of an operator

```sh
(do (sh-eval "printf '%s\\n' \"$(((1+2)*(3+4)))\"") ())
```
---
    21

### a single bar and a doubled one in one expression

```sh
(do (sh-eval "printf '%s\\n' \"$((0|1||0))\"") ())
```
---
    1

### a skipped division inside a chain of `||`

```sh
(do (sh-eval "printf '%s\\n' \"$((0&&1/0||1))\"") ())
```
---
    1

### a skipped `&&` on the right of `||`

```sh
(do (sh-eval "printf '%s\\n' \"$((1||1/0&&0))\"") ())
```
---
    1

### a sum, a shift and an equality test

```sh
(do (sh-eval "printf '%s\\n' \"$((2+3<<1==10))\"") ())
```
---
    1

### equality tests group to the left

```sh
(do (sh-eval "printf '%s\\n' \"$((1==1!=0))\"") ())
```
---
    1

### a remainder and a product group to the left

```sh
(do (sh-eval "printf '%s\\n' \"$((7%4*3))\"") ())
```
---
    9

### an operator costs the same to read at any rank

What is compared is the heap each reading allocates: sixteen operands joined
by `||`, the loosest operator, against sixteen joined by `*`, the tightest.

```sh
(do
  (sh-eval "v=$((1||1)); v=$((1*1))")
  (let ((cost (fn (_ text)
                (let ((before (Heap count)))
                  (sh-eval text)
                  (- (Heap count) before)))))
    (let ((loose (cost "v=$((1||1||1||1||1||1||1||1||1||1||1||1||1||1||1||1))"))
          (tight (cost "v=$((1*1*1*1*1*1*1*1*1*1*1*1*1*1*1*1))")))
      (< loose (* 2 tight)))))
```
---
    #t
