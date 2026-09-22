## sh-eval set -a

`set -a`, or `set -o allexport`, gives every variable assigned while it is on
the export attribute, however the assignment is made: plainly, by `read`, by
`for`, or by `${name:=word}`.  A name exported that way stays exported after
`set +a`.  `$-` holds `a` while it is on.

Expectations match `/bin/sh` and `dash`.

### an assignment is exported

```sh
(do (sh-eval "( set -a; auto=1; sh -c 'echo \"[$auto]\"' )") ())
```
---
    [1]

### a file of assignments, sourced

```sh
(do (sh-eval "( f=$(mktemp); printf 'A=1\\nB=2\\n' > \"$f\"; set -a; . \"$f\"; set +a; rm -f \"$f\"; sh -c 'echo \"[$A$B]\"' )") ())
```
---
    [12]

### nothing is exported once it is off

```sh
(do (sh-eval "( set -a; set +a; y=2; sh -c 'echo \"[$y]\"' )") ())
```
---
    []

### by its long name

```sh
(do (sh-eval "( set -o allexport; z=3; sh -c 'echo \"[$z]\"' )") ())
```
---
    [3]

### read assigns

```sh
(do (sh-eval "( set -a; read r <<EOF\nval\nEOF\nsh -c 'echo \"[$r]\"'\n)") ())
```
---
    [val]

### for assigns

```sh
(do (sh-eval "( set -a; for v in x; do :; done; sh -c 'echo \"[$v]\"' )") ())
```
---
    [x]

### ${name:=word} assigns

```sh
(do (sh-eval "( unset w; set -a; : ${w:=dflt}; sh -c 'echo \"[$w]\"' )") ())
```
---
    [dflt]

### an arithmetic result is assigned like any value

```sh
(do (sh-eval "( set -a; n=$((5+1)); sh -c 'echo \"[$n]\"' )") ())
```
---
    [6]

### a name exported under -a stays exported

```sh
(do (sh-eval "( set -a; q=1; set +a; q=2; sh -c 'echo \"[$q]\"' )") ())
```
---
    [2]

### a name the shell already had moves to the environment

```sh
(do (sh-eval "( x=1; set -a; x=2; echo \"$x\"; sh -c 'echo \"[$x]\"' )") ())
```
---
    [2]

### $- holds a

```sh
(do (sh-eval "( set -a; case $- in *a*) echo has-a;; esac )") ())
```
---
    has-a
