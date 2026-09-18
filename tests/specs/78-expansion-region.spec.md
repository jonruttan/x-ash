## sh-eval a parameter expansion is read as one unit

The text from `${` to its matching `}` is one unit, read with quoting of its
own: the `"` in `"${x:-"a b"}"` opens a string inside the expansion rather
than closing the one around it, and the space in `${x:-a b}` does not end the
word.  Braces nest -- `${x:-${y:-z}}`, `${x:-{a}}` -- and a quote or a
backslash hides one from the count.

Each case unsets what it expects unset: the suite runs several files in one
shell.

Expectations match `/bin/sh` and `dash`.

### a nested string with a space, inside quotes

```sh
(do (sh-eval "( unset x; echo \"${x:-\"quoted default\"}\" )") ())
```
---
    quoted default

### the alternate form

```sh
(do (sh-eval "( y=v; echo \"${y:+\"has $y\"}\" )") ())
```
---
    has v

### the form without a colon

```sh
(do (sh-eval "( unset x; echo \"${x-\"dash form\"}\" )") ())
```
---
    dash form

### an unquoted space in a default, split afterwards as a value is

```sh
(do (sh-eval "( unset x; set -- ${x:-a b}; echo \"$#:$1\" )") ())
```
---
    2:a

### braces that pair

```sh
(do (sh-eval "( unset x; echo ${x:-{a}} \"${x:-{b}}\" )") ())
```
---
    {a} {b}

### an expansion inside an expansion

```sh
(do (sh-eval "( unset x y; echo \"${x:-${y:-z}}\" )") ())
```
---
    z

### a substitution with its own quotes inside one

```sh
(do (sh-eval "( unset x; echo \"${x:-$(echo \"a b\")}\" )") ())
```
---
    a b

### text around it stays one word

```sh
(do (sh-eval "( unset x; echo \"pre${x:-\"m i d\"}post\" )") ())
```
---
    prem i dpost

### a set value leaves the word unused

```sh
(do (sh-eval "( x=set; echo \"${x:-\"unused one\"}\" )") ())
```
---
    set

### a length inside quotes

```sh
(do (sh-eval "( echo \"${#HOME}\" | grep -c '^[0-9]' )") ())
```
---
    1

### and the word after it is its own

```sh
(do (sh-eval "( unset x; echo \"${x:-a}\" b )") ())
```
---
    a b
