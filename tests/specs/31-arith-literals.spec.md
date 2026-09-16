## sh-eval arithmetic integer literals

`$(( ))` reads three forms of integer: `0x` or `0X` and hexadecimal digits, a
leading `0` and octal digits, and otherwise decimal.  A variable's value is
read the same way, so `v=0x20` counts as thirty-two.

A digit the base does not have is an error.  `08` is a typo for either `8` or
`010`, and answering one of them would be a guess.

Expectations match `/bin/sh` and `dash`.

### hexadecimal

```sh
(do (sh-eval "printf '%s\\n' \"$((0x10))\"") ())
```
---
    16

### an upper-case prefix and upper-case digits

```sh
(do (sh-eval "printf '%s\\n' \"$((0X1f))\"") ())
```
---
    31

### octal

```sh
(do (sh-eval "printf '%s\\n' \"$((010))\"") ())
```
---
    8

### a single zero is zero, not an empty octal

```sh
(do (sh-eval "printf '%s\\n' \"$((0))\"") ())
```
---
    0

### and so is a doubled zero

```sh
(do (sh-eval "printf '%s\\n' \"$((00))\"") ())
```
---
    0

### a sign applies to the whole literal

```sh
(do (sh-eval "printf '%s\\n' \"$((-0x10))\"") ())
```
---
    -16

### hexadecimal takes part in arithmetic

```sh
(do (sh-eval "printf '%s\\n' \"$((0x10+1))\"") ())
```
---
    17

### so does octal

```sh
(do (sh-eval "printf '%s\\n' \"$((017+1))\"") ())
```
---
    16

### a variable's value is read in the same three forms

```sh
(do (sh-eval "v=0x20; printf '%s\\n' \"$((v))\"") ())
```
---
    32

### including octal

```sh
(do (sh-eval "w=010; printf '%s\\n' \"$((w+0))\"") ())
```
---
    8

### hexadecimal reaches the bitwise operators

```sh
(do (sh-eval "printf '%s\\n' \"$((0xff&0x0f))\"") ())
```
---
    15

### and a shift count may be written in hexadecimal

```sh
(do (sh-eval "printf '%s\\n' \"$((1<<0x4))\"") ())
```
---
    16

### a digit the base does not have is refused

The refusal is read through a command substitution: the expansion fails in
the child, so the value is empty and the script carries on.  Reading it as a
status instead would be reading this suite's harness rather than the shell.

```sh
(do (sh-eval "v=$( printf '%s' \"$((08))\" 2>/dev/null ); printf 'v=[%s]\\n' \"$v\"") ())
```
---
    v=[]

### a name that is not a number is still zero

```sh
(do (sh-eval "v=abc; printf '%s\\n' \"$((v))\"") ())
```
---
    0
