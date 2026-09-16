## sh-eval arithmetic bitwise operators

`&`, `|`, `^`, `<<`, `>>` and unary `~` complete the integer operators POSIX
gives `$(( ))`.  They bind between `&&` and the equality tests, and the
shifts between the comparisons and `+`.

Each operator is a row in the table and its name a row in the precedence
list; the list of names the scanner matches is taken from the precedence
list, so the two cannot drift apart.

The scanner takes the longest operator written at a position, whatever its
precedence.  Asking one level at a time would read `a||b` as a bitwise or,
because `|` binds tighter and its level is tried first.

Expectations match `/bin/sh` and `dash`.

### and

```sh
(do (sh-eval "printf '%s\\n' \"$((6&3))\"") ())
```
---
    2

### or

```sh
(do (sh-eval "printf '%s\\n' \"$((6|3))\"") ())
```
---
    7

### exclusive or

```sh
(do (sh-eval "printf '%s\\n' \"$((6^3))\"") ())
```
---
    5

### shift left

```sh
(do (sh-eval "printf '%s\\n' \"$((1<<4))\"") ())
```
---
    16

### shift right

```sh
(do (sh-eval "printf '%s\\n' \"$((255>>4))\"") ())
```
---
    15

### complement

```sh
(do (sh-eval "printf '%s\\n' \"$((~0))\"") ())
```
---
    -1

### a doubled character is still the logical operator

```sh
(do (sh-eval "printf '%s\\n' \"$((1||0))\"") ())
```
---
    1

### and so is the doubled ampersand

```sh
(do (sh-eval "printf '%s\\n' \"$((1&&0))\"") ())
```
---
    0

### one angle bracket compares, two shift

```sh
(do (sh-eval "printf '%s,%s\\n' \"$((1<2))\" \"$((1<<2))\"") ())
```
---
    1,4

### and binds tighter than or

```sh
(do (sh-eval "printf '%s\\n' \"$((1|2&3))\"") ())
```
---
    3

### exclusive or binds tighter than or

```sh
(do (sh-eval "printf '%s\\n' \"$((1^1|2))\"") ())
```
---
    2

### addition binds tighter than a shift

```sh
(do (sh-eval "printf '%s\\n' \"$((1<<2+1))\"") ())
```
---
    8

### equality binds tighter than and

```sh
(do (sh-eval "printf '%s\\n' \"$((3&1==1))\"") ())
```
---
    1

### parentheses override the order

```sh
(do (sh-eval "printf '%s\\n' \"$(( (1|2)&3 ))\"") ())
```
---
    3

### the complement of zero masks to all ones

```sh
(do (sh-eval "printf '%s\\n' \"$((~0&255))\"") ())
```
---
    255
