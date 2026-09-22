## sh-eval an expansion's edges

An unquoted expansion joins the text either side of it unless it begins or
ends with an IFS character: `p${x}q` is one field when x holds none.  One at
the start closes the field before the expansion, and one at the end closes the
expansion's last field, so what follows starts another.  Only a character of
IFS counts -- with IFS=: a space is text, and with IFS empty nothing splits.
A start that holds a delimiter other than whitespace closes the field before
it once, whatever whitespace comes with it.

Expectations match `/bin/sh` and `dash`.

### a space is text when IFS does not hold it

```sh
(do (sh-eval "( IFS=:; x=\" a \"; set -- p${x}q; echo \"$# [$1]\" )") ())
```
---
    1 [p a q]

### a value of spaces alone, the same

```sh
(do (sh-eval "( IFS=:; x=\" \"; set -- p${x}q; echo \"$# [$1]\" )") ())
```
---
    1 [p q]

### with IFS empty nothing splits at the edges either

```sh
(do (sh-eval "( IFS=; x=\" a:b \"; set -- p${x}q; echo \"$# [$1]\" )") ())
```
---
    1 [p a:b q]

### a delimiter at the end closes the field

```sh
(do (sh-eval "( IFS=:; x=\"a:\"; set -- ${x}q; echo \"$# [$1] [$2]\" )") ())
```
---
    2 [a] [q]

### a delimiter alone closes the field either side

```sh
(do (sh-eval "( IFS=:; x=\":\"; set -- p${x}q; echo \"$# [$1] [$2]\" )") ())
```
---
    2 [p] [q]

### an empty field before a delimiter at the end

```sh
(do (sh-eval "( IFS=:; x=\"a::\"; set -- ${x}q; echo \"$# [$1] [$2] [$3]\" )") ())
```
---
    3 [a] [] [q]

### the same value alone makes no field after its last delimiter

```sh
(do (sh-eval "( IFS=:; x=\"a::\"; set -- $x; echo \"$# [$1] [$2]\" )") ())
```
---
    2 [a] []

### one value's end meets the next one's start

```sh
(do (sh-eval "( IFS=:; x=\"a:\"; y=b; set -- $x$y; echo \"$# [$1] [$2]\" )") ())
```
---
    2 [a] [b]

### whitespace before a delimiter is part of it

```sh
(do (sh-eval "( IFS=\" :\"; x=\" :a\"; set -- p$x; echo \"$# [$1] [$2]\" )") ())
```
---
    2 [p] [a]

### whitespace either side of a delimiter is part of it

```sh
(do (sh-eval "( IFS=\" :\"; x=\" : \"; set -- p${x}q; echo \"$# [$1] [$2]\" )") ())
```
---
    2 [p] [q]

### IFS whitespace at the edges closes the fields either side

```sh
(do (sh-eval "( x=\" a b \"; set -- p${x}q; echo \"$# [$1] [$2] [$3] [$4]\" )") ())
```
---
    4 [p] [a] [b] [q]
