## sh-eval set -C and >|

`set -C`, or `set -o noclobber`, keeps `>` from writing over a regular file
that is already there: the redirection is refused and the file keeps what it
held.  A file that is not there is created only if it is still not there when
it is opened, which is what makes `( : > lock )` a lock.  A file that is not
regular, such as `/dev/null`, is written to as it is, and `>>` appends as it
always does.  `>|` writes over the file whatever the option says.  `$-` holds
`C` while it is on.

Expectations match `/bin/sh` and `dash`.  The status of a refused redirection
is not asserted: dash answers 2 and bash 1.

### > is refused on a file that is there

```sh
(do (sh-eval "( f=$(mktemp); set -C; ( echo x > \"$f\" ) 2>/dev/null || echo refused; rm -f \"$f\" )") ())
```
---
    refused

### and the file keeps what it held

```sh
(do (sh-eval "( f=$(mktemp); echo keep > \"$f\"; set -C; ( echo lost > \"$f\" ) 2>/dev/null; cat \"$f\"; rm -f \"$f\" )") ())
```
---
    keep

### by its long name

```sh
(do (sh-eval "( f=$(mktemp); set -o noclobber; ( echo x > \"$f\" ) 2>/dev/null || echo refused-long; rm -f \"$f\" )") ())
```
---
    refused-long

### a lock taken twice

```sh
(do (sh-eval "( d=$(mktemp -d); set -C; if ( : > \"$d/lock\" ) 2>/dev/null; then echo got-lock; fi; if ( : > \"$d/lock\" ) 2>/dev/null; then echo twice; else echo held; fi; rm -rf \"$d\" )") ())
```
---
    held

### >| writes over it

```sh
(do (sh-eval "( f=$(mktemp); set -C; echo y >| \"$f\"; echo \"[$(cat \"$f\")]\"; rm -f \"$f\" )") ())
```
---
    [y]

### >| writes to its file without the option too

```sh
(do (sh-eval "( f=$(mktemp); echo y >| \"$f\"; echo \"[$(cat \"$f\")]\"; rm -f \"$f\" )") ())
```
---
    [y]

### $- holds C

```sh
(do (sh-eval "( set -C; case $- in *C*) echo has-C;; esac )") ())
```
---
    has-C

### a file that is not there is created

```sh
(do (sh-eval "( d=$(mktemp -d); set -C; echo new > \"$d/n\"; cat \"$d/n\"; rm -rf \"$d\" )") ())
```
---
    new

### /dev/null takes output

```sh
(do (sh-eval "( set -C; echo x > /dev/null && echo devnull-ok )") ())
```
---
    devnull-ok

### >> appends

```sh
(do (sh-eval "( f=$(mktemp); set -C; echo a >> \"$f\"; cat \"$f\"; rm -f \"$f\" )") ())
```
---
    a

### set +C turns it off

```sh
(do (sh-eval "( f=$(mktemp); set -C; set +C; echo z > \"$f\"; cat \"$f\"; rm -f \"$f\" )") ())
```
---
    z
