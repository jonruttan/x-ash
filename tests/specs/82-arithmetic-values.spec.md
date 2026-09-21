## sh-eval a variable's value in arithmetic

A name in `$(( ))` stands for its variable's value read as an integer
constant: blanks around it are dropped and a sign may stand in front, since
`$((n))` answers what `$(($n))` does.  That is what reads a count from a `wc`
that pads it.  An empty value is 0.

Expectations match `/bin/sh` and `dash`.

### leading blanks

```sh
(do (sh-eval "( n='   3'; echo $((n)) )") ())
```
---
    3

### trailing blanks

```sh
(do (sh-eval "( n='3   '; echo $((n + 1)) )") ())
```
---
    4

### a sign inside the blanks

```sh
(do (sh-eval "( n=' -3 '; echo $((n * 2)) )") ())
```
---
    -6

### a plus sign

```sh
(do (sh-eval "( n='+3'; echo $((n)) )") ())
```
---
    3

### a negative octal constant

```sh
(do (sh-eval "( n='-010'; echo $((n)) )") ())
```
---
    -8

### a padded hexadecimal constant

```sh
(do (sh-eval "( n=' 0x10 '; echo $((n)) )") ())
```
---
    16

### tabs

```sh
(do (sh-eval "( n=$(printf '\\t3\\t'); echo $((n)) )") ())
```
---
    3

### a count from wc

```sh
(do (sh-eval "( n=$(printf 'abc' | wc -c); echo $((n)) )") ())
```
---
    3

### an assignment operator reads the value the same way

```sh
(do (sh-eval "( n=' 5 '; : $((n += 1)); echo \"$n\" )") ())
```
---
    6

### blanks alone are 0

```sh
(do (sh-eval "( n='  '; echo $((n + 1)) )") ())
```
---
    1
