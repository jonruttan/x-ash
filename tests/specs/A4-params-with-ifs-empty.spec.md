## sh-eval `$@` and `$*` with IFS empty

Unquoted, `$@` and `$*` are the parameters joined on IFS's first character,
which field splitting splits apart again.  With IFS empty there is no
character to join on and nothing splits, so each parameter is a field of its
own, not split further: the first joins the text before it and the last the
text after it, and an empty parameter makes no field but still ends the one
before it.  Where nothing is split -- an assignment, a `case` word -- the
parameters are joined as before.

Expectations match `/bin/sh` and `dash`.  `P` prints each of its arguments in
brackets.

### `$*` keeps the parameters apart

```sh
(do (sh-eval "( P() { for w in \"$@\"; do printf \"[%s]\" \"$w\"; done; echo; }; IFS=; set -- \"a b\" c; P $* )") ())
```
---
    [a b][c]

### and so does `$@`

```sh
(do (sh-eval "( P() { for w in \"$@\"; do printf \"[%s]\" \"$w\"; done; echo; }; IFS=; set -- \"a b\" c; P $@ )") ())
```
---
    [a b][c]

### the text either side joins the first and last

```sh
(do (sh-eval "( P() { for w in \"$@\"; do printf \"[%s]\" \"$w\"; done; echo; }; IFS=; set -- a b; P x$*y x${@}y )") ())
```
---
    [xa][by][xa][by]

### an empty parameter still ends the field before it

```sh
(do (sh-eval "( P() { for w in \"$@\"; do printf \"[%s]\" \"$w\"; done; echo; }; IFS=; set -- \"\" \"\"; P x$*y )") ())
```
---
    [x][y]

### and makes no field of its own

```sh
(do (sh-eval "( P() { for w in \"$@\"; do printf \"[%s]\" \"$w\"; done; echo; }; IFS=; set -- \"\" a \"\"; P $* \"<\" )") ())
```
---
    [a][<]

### blanks inside a parameter stay

```sh
(do (sh-eval "( P() { for w in \"$@\"; do printf \"[%s]\" \"$w\"; done; echo; }; IFS=; set -- \" a \" b; P $* )") ())
```
---
    [ a ][b]

### two expansions meet in one field

```sh
(do (sh-eval "( P() { for w in \"$@\"; do printf \"[%s]\" \"$w\"; done; echo; }; IFS=; set -- a b; P \"$@\"$* )") ())
```
---
    [a][ba][b]

### a parameter is still a pattern

```sh
(do (sh-eval "( P() { for w in \"$@\"; do printf \"[%s]\" \"$w\"; done; echo; }; IFS=; set -- \"a*\" c; cd /; P $* )") ())
```
---
    [a*][c]

### an assignment joins them

```sh
(do (sh-eval "( IFS=; set -- \"a b\" c; x=$*; printf \"{%s}\" \"$x\"; echo )") ())
```
---
    {a bc}

### quoted, they are what they were

```sh
(do (sh-eval "( P() { for w in \"$@\"; do printf \"[%s]\" \"$w\"; done; echo; }; IFS=; set -- a b; P \"$*\" \"$@\" )") ())
```
---
    [ab][a][b]
