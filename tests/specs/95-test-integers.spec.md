## sh-eval test's integers

An operand of `-eq`, `-ne`, `-lt`, `-le`, `-gt` or `-ge` is decimal digits,
with a sign in front and blanks around them allowed: `010` is ten, and `0x10`
is no integer at all.  An operand that is not one is a usage error, 2, and
the comparison is not made.

Expectations match `/bin/sh` and `dash`.

### blanks before the digits

```sh
(do (sh-eval "( [ \" 5\" -eq 5 ] && echo lead-blank-ok )") ())
```
---
    lead-blank-ok

### blanks after them

```sh
(do (sh-eval "( [ \"5 \" -eq 5 ] && echo trail-blank-ok )") ())
```
---
    trail-blank-ok

### a minus sign

```sh
(do (sh-eval "( [ -5 -lt 0 ] && echo negative-ok )") ())
```
---
    negative-ok

### a plus sign

```sh
(do (sh-eval "( [ +5 -eq 5 ] && echo plus-ok )") ())
```
---
    plus-ok

### a leading zero is still decimal

```sh
(do (sh-eval "( [ 010 -eq 10 ] && echo decimal-ok )") ())
```
---
    decimal-ok

### hexadecimal is no integer

```sh
(do (sh-eval "( [ 0x10 -eq 16 ] 2>/dev/null; echo \"hex=$?\" )") ())
```
---
    hex=2

### nor is a word

```sh
(do (sh-eval "( [ abc -eq 1 ] 2>/dev/null; echo \"word=$?\" )") ())
```
---
    word=2

### nor nothing

```sh
(do (sh-eval "( [ \"\" -eq 0 ] 2>/dev/null; echo \"empty=$?\" )") ())
```
---
    empty=2

### nor digits with more after them

```sh
(do (sh-eval "( [ 5 -eq 5x ] 2>/dev/null; echo \"trail-junk=$?\" )") ())
```
---
    trail-junk=2

### a large number

```sh
(do (sh-eval "( [ 99999999999 -gt 1 ] && echo big-ok )") ())
```
---
    big-ok

### minus zero

```sh
(do (sh-eval "( [ -0 -eq 0 ] && echo minus-zero-ok )") ())
```
---
    minus-zero-ok

### a counter as a loop compares it

```sh
(do (sh-eval "( i=7; [ $i -lt 50 ] && [ $i -ge 7 ] && [ $i -ne 8 ] && echo loop-ok )") ())
```
---
    loop-ok
