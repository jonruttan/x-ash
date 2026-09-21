## sh-eval test expressions

`test` and `[` read up to four words by how many there are, as POSIX sets
out: with three, a binary operator in the middle decides first, `-a` and `-o`
among them; with four, `!` negates the three after it and parentheses group
two.  More words are an expression: `!` binds tighter than `-a`, `-a` tighter
than `-o`, and `(` `)` group.  Words left over are a usage error, 2.

Expectations match `/bin/sh` and `dash`.

### -a joins two tests

```sh
(do (sh-eval "( [ -n \"a\" -a -n \"b\" ] && echo and-ok )") ())
```
---
    and-ok

### -o joins two tests

```sh
(do (sh-eval "( [ -z \"a\" -o -n \"b\" ] && echo or-ok )") ())
```
---
    or-ok

### parentheses group

```sh
(do (sh-eval "( test \\( -n \"x\" -a -z \"\" \\) -o 1 = 2 && echo paren-test )") ())
```
---
    paren-test

### -a binds tighter than -o

```sh
(do (sh-eval "( [ -n \"\" -a -n \"\" -o -n x ] && echo prec )") ())
```
---
    prec

### ! binds tighter than -a

```sh
(do (sh-eval "( [ ! -n x -a -n \"\" ] || echo not-binds )") ())
```
---
    not-binds

### three words with -a and -o in the middle

```sh
(do (sh-eval "( [ a -a b ] && [ \"\" -o x ] && echo three-words )") ())
```
---
    three-words

### three words compare first, so ! can be a string

```sh
(do (sh-eval "( [ ! = x ] || echo bang-compare )") ())
```
---
    bang-compare

### four words in parentheses

```sh
(do (sh-eval "( [ \\( -n x \\) ] && echo four-paren )") ())
```
---
    four-paren

### a word left over is a usage error

```sh
(do (sh-eval "( [ a = a b ]; echo \"s=$?\" ) 2>/dev/null") ())
```
---
    s=2

### a usage error under ! stays one

```sh
(do (sh-eval "( [ ! -q x ]; echo \"s=$?\" ) 2>/dev/null") ())
```
---
    s=2

### numeric comparisons joined

```sh
(do (sh-eval "( x=5; [ \"$x\" -lt 3 -o \"$x\" -gt 4 ] && echo range )") ())
```
---
    range

### file tests joined

```sh
(do (sh-eval "( [ -d / -a -e / ] && echo dirs )") ())
```
---
    dirs

### a group joined to a negation

```sh
(do (sh-eval "( [ \\( a = b -o b = b \\) -a ! -z x ] && echo nested )") ())
```
---
    nested

### ! before a group negates the group

```sh
(do (sh-eval "( [ ! \\( -n x -o -n y \\) ] || echo negated-group )") ())
```
---
    negated-group
