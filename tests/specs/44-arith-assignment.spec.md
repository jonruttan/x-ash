## sh-eval arithmetic assignment

`$(( ))` assigns with `=` and with the assigning form of a binary operator:
`+=`, `-=`, `*=`, `/=`, `%=`, `<<=`, `>>=`, `&=`, `^=` and `|=`.  The left side
is a variable name.  The value of the assignment is the value assigned, which
the variable holds afterwards as a decimal number.

Assignment is the loosest expression and groups to the right, so `x = y = 3`
sets both and `x = c ? a : b` assigns the conditional's answer.  It stands
wherever a whole expression may -- the top of the expansion, inside
parentheses, and the first branch of a conditional -- but not as the second
branch.  A comparison that starts like an assignment operator, `==` or `<=`,
is the comparison.

A branch that is not taken assigns nothing.  The expansion is one expression,
so text left after it is refused rather than skipped.

A refusal is read through a command substitution: the expansion fails in the
child, and the value is empty.

Expectations match `/bin/sh` and `dash`.

### = assigns, and answers the value

```sh
(do (sh-eval "x=1; echo \"[$((x=5))][$x]\"") ())
```
---
    [5][5]

### += adds to the variable

```sh
(do (sh-eval "x=1; echo \"[$((x+=2))][$x]\"") ())
```
---
    [3][3]

### -=, *=, /= and %=

```sh
(do (sh-eval "x=7; echo \"[$((x-=2))][$((x*=3))][$((x/=4))][$((x%=3))][$x]\"") ())
```
---
    [5][15][3][0][0]

### the shift assignments

```sh
(do (sh-eval "x=1; echo \"[$((x<<=3))][$((x>>=1))][$x]\"") ())
```
---
    [8][4][4]

### the bitwise assignments

```sh
(do (sh-eval "x=12; echo \"[$((x&=10))][$((x|=1))][$((x^=3))][$x]\"") ())
```
---
    [8][9][10][10]

### assignment groups to the right

```sh
(do (sh-eval "unset x y; echo \"[$((x=y=3))][$x][$y]\"") ())
```
---
    [3][3][3]

### and chains

```sh
(do (sh-eval "unset x y z; echo \"[$(( x = y = z = 7 ))][$x$y$z]\"") ())
```
---
    [7][777]

### an unset variable counts as zero

```sh
(do (sh-eval "unset x; echo \"[$((x+=1))][$x]\"") ())
```
---
    [1][1]

### the right side reads the old value

```sh
(do (sh-eval "x=5; echo \"[$(( x=x+1 ))][$x]\"") ())
```
---
    [6][6]

### the variable on both sides

```sh
(do (sh-eval "x=3; echo \"[$(( x += x ))][$x]\"") ())
```
---
    [6][6]

### the value is read in its base

```sh
(do (sh-eval "unset x; echo \"[$(( x = 010 ))][$x]\"") ())
```
---
    [8][8]

### spaces around the operator

```sh
(do (sh-eval "unset x; echo \"[$((  x  +=  4  ))][$x]\"") ())
```
---
    [4][4]

### comparisons are not assignments

```sh
(do (sh-eval "x=1; echo \"[$((x == 1))][$((x <= 1))][$((x != 2))][$x]\"") ())
```
---
    [1][1][1][1]

### == leaves an unset variable unset

```sh
(do (sh-eval "unset x; echo \"[$(( x == 0 ))][${x-unset}]\"") ())
```
---
    [1][unset]

### <<= assigns where >= compares

```sh
(do (sh-eval "x=2; echo \"[$(( x <<= 1 ))][$(( x >= 4 ))][$x]\"") ())
```
---
    [4][1][4]

### assignment is looser than the conditional

```sh
(do (sh-eval "unset x; echo \"[$((x = 1 ? 2 : 3))][$x]\"") ())
```
---
    [2][2]

### and looser than ||

```sh
(do (sh-eval "unset x; echo \"[$((x = 0 || 5))][$x]\"") ())
```
---
    [1][1]

### a parenthesised assignment is an operand

```sh
(do (sh-eval "unset x; echo \"[$(( (x=4) + 1 ))][$x]\"") ())
```
---
    [5][4]

### and may sit inside a sum

```sh
(do (sh-eval "x=1; echo \"[$(( 2 + (x += 3) ))][$x]\"") ())
```
---
    [6][4]

### the first branch of a conditional may assign

```sh
(do (sh-eval "unset x; echo \"[$(( 1 ? x=2 : 3 ))][$x]\"") ())
```
---
    [2][2]

### a branch && skips assigns nothing

```sh
(do (sh-eval "unset x; echo \"[$(( 0 && (x=5) ))][${x-unset}]\"") ())
```
---
    [0][unset]

### nor does one || skips

```sh
(do (sh-eval "unset x; echo \"[$(( 1 || (x=5) ))][${x-unset}]\"") ())
```
---
    [1][unset]

### nor a conditional's untaken branch

```sh
(do (sh-eval "unset x y; echo \"[$(( 0 ? x=1 : (y=2) ))][${x-unset}][$y]\"") ())
```
---
    [2][unset][2]

### the expansion assigns in this shell

```sh
(do (sh-eval "x=5; y=$((x*=2)); echo \"[$y][$x]\"") ())
```
---
    [10][10]

### a counter in a function

```sh
(do (sh-eval "f() { : $((cnt+=1)); }; cnt=0; f; f; f; echo \"[$cnt]\"") ())
```
---
    [3]

### the second branch of a conditional may not assign

```sh
(do (sh-eval "unset y; v=$(echo \"$(( 0 ? 1 : y=2 ))\" 2>/dev/null); echo \"[$v][${y-unset}]\"") ())
```
---
    [][unset]

### a number is not a variable

```sh
(do (sh-eval "v=$(echo \"$((1=2))\" 2>/dev/null); echo \"[$v]\"") ())
```
---
    []

### an assignment that divides by zero is refused

```sh
(do (sh-eval "x=2; v=$(echo \"$(( x /= 0 ))\" 2>/dev/null); echo \"[$v]\"") ())
```
---
    []

### text after a whole expression is refused

```sh
(do (sh-eval "v=$(echo \"$((1 2))\" 2>/dev/null); echo \"[$v]\"") ())
```
---
    []

