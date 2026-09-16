## sh-eval arithmetic conditional

`$(( c ? a : b ))` answers `a` when `c` is non-zero and `b` when it is zero.
It binds looser than every binary operator and groups to the right, so
`a ? b : c ? d : e` is `a ? b : (c ? d : e)`.

Only the branch taken is evaluated.  C defines the operator that way and
POSIX defers to C for `$(( ))`, which is what makes `$(( n ? sum/n : 0 ))` a
guard rather than a division.  `&&` and `||` skip their right operand once
the left has decided the answer, for the same reason.

A branch that is not taken is still read, because what it skips is the
arithmetic and not the spelling: `08` is refused wherever it is written.  A
name in such a branch is a different matter — its value is data the branch
never asks for, so `u=08` is only a bad literal where `u` is actually read.

Expectations match `dash`.

### a non-zero condition answers the first branch

```sh
(do (sh-eval "printf '%s\\n' \"$((1?2:3))\"") ())
```
---
    2

### a zero condition answers the second

```sh
(do (sh-eval "printf '%s\\n' \"$((0?2:3))\"") ())
```
---
    3

### any non-zero value is a true condition

```sh
(do (sh-eval "printf '%s\\n' \"$((-1?5:6))\"") ())
```
---
    5

### the operator groups to the right

```sh
(do (sh-eval "printf '%s\\n' \"$((0?2:0?4:5))\"") ())
```
---
    5

### the first branch may hold a conditional of its own

```sh
(do (sh-eval "printf '%s\\n' \"$(( 2>1 ? 2<1 ? 8 : 9 : 10 ))\"") ())
```
---
    9

### the condition is a whole expression

```sh
(do (sh-eval "printf '%s\\n' \"$((1+1?10:20))\"") ())
```
---
    10

### so is a branch

```sh
(do (sh-eval "printf '%s\\n' \"$((0?1:2+3))\"") ())
```
---
    5

### it binds looser than the logical operators

```sh
(do (sh-eval "printf '%s\\n' \"$(( 0 || 0 ? 7 : 8 ))\"") ())
```
---
    8

### a signed branch is read as one term

```sh
(do (sh-eval "printf '%s\\n' \"$((1?-2:3))\"") ())
```
---
    -2

### parentheses make it a term of a larger expression

```sh
(do (sh-eval "printf '%s\\n' \"$(( (1?2:3)+10 ))\"") ())
```
---
    12

### and a parenthesised conditional may be another's condition

```sh
(do (sh-eval "printf '%s\\n' \"$(( (0?1:2) ? 30 : 40 ))\"") ())
```
---
    30

### the branch not taken is not evaluated

```sh
(do (sh-eval "n=0; printf '%s\\n' \"$(( n ? 100/n : 0 ))\"") ())
```
---
    0

### the branch taken is

```sh
(do (sh-eval "n=4; printf '%s\\n' \"$(( n ? 100/n : 0 ))\"") ())
```
---
    25

### a division in a first branch is skipped the same way

```sh
(do (sh-eval "printf '%s\\n' \"$(( 0 ? u/0 : 9 ))\"") ())
```
---
    9

### `&&` stops once the left operand is zero

```sh
(do (sh-eval "c=0; printf '%s\\n' \"$(( c && 100/c ))\"") ())
```
---
    0

### `||` stops once the left operand is not

```sh
(do (sh-eval "printf '%s\\n' \"$(( 1 || 1/0 ))\"") ())
```
---
    1

### a skipped `&&` still answers one or zero

```sh
(do (sh-eval "printf '%s\\n' \"$(( 1 && 2 ))\"") ())
```
---
    1

### and so does `||`

```sh
(do (sh-eval "printf '%s\\n' \"$(( 0 || 3 ))\"") ())
```
---
    1

### a literal the base does not have is refused in a branch not taken

The refusal is read through a command substitution: the expansion fails in
the child, so the value is empty and the script carries on.

```sh
(do (sh-eval "v=$( printf '%s' \"$(( 1 ? 1 : 08 ))\" 2>/dev/null ); printf 'v=[%s]\\n' \"$v\"") ())
```
---
    v=[]

### and in a first branch not taken

```sh
(do (sh-eval "w=$( printf '%s' \"$(( 0 ? 08 : 1 ))\" 2>/dev/null ); printf 'w=[%s]\\n' \"$w\"") ())
```
---
    w=[]

### a name in a branch not taken is not read, so its value is not a literal there

```sh
(do (sh-eval "u=08; printf '%s\\n' \"$(( 0 ? u : 1 ))\"") ())
```
---
    1

### the same name in the branch taken is refused

```sh
(do (sh-eval "u=08; v=$( printf '%s' \"$(( 1 ? u : 1 ))\" 2>/dev/null ); printf 'v=[%s]\\n' \"$v\"") ())
```
---
    v=[]
