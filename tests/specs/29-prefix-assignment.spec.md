## sh-eval a prefix assignment covers one command

`NAME=value command` puts NAME in the environment the command runs in and
leaves the shell's own value alone.  Without a command the assignment is the
shell's from then on, which is the ordinary way to set a variable.

A special builtin is the exception POSIX names: an assignment in front of one
outlives it, so `X=1 export Y=2` leaves X set.

After a function call the two reference shells disagree and POSIX leaves it
unspecified; this follows dash and restores the shell's value.

### the shell's value is untouched afterwards

```sh
(do (sh-eval "( ASH_A=1 true; printf '[%s]\\n' \"$ASH_A\" )") ())
```
---
    []

### with no command it is the shell's value

```sh
(do (sh-eval "( ASH_B=2; printf '[%s]\\n' \"$ASH_B\" )") ())
```
---
    [2]

### the command runs with it

```sh
(do (sh-eval "( g() { printf '[%s]\\n' \"$G1\"; }; G1=seen g )") ())
```
---
    [seen]

### an earlier value comes back, rather than being unset

```sh
(do (sh-eval "( ASH_C=old; ASH_C=new true; printf '[%s]\\n' \"$ASH_C\" )") ())
```
---
    [old]

### several assignments all come back

```sh
(do (sh-eval "( ASH_D=a ASH_E=b true; printf '[%s][%s]\\n' \"$ASH_D\" \"$ASH_E\" )") ())
```
---
    [][]

### a regular builtin does not keep it

```sh
(do (sh-eval "( ASH_F=p read junk </dev/null; printf '[%s]\\n' \"$ASH_F\" )") ())
```
---
    []

### a special builtin does keep it

```sh
(do (sh-eval "( ASH_G=r export ASH_H=q; printf '[%s][%s]\\n' \"$ASH_G\" \"$ASH_H\" )") ())
```
---
    [r][q]

### IFS in front of read covers that read only

```sh
(do (sh-eval "( printf 'p:q\\n' | { IFS=: read a b; printf '[%s][%s]\\n' \"$a\" \"$b\"; } )") ())
```
---
    [p][q]

### and the read after it splits on IFS again

```sh
(do (sh-eval "( printf 'p:q\\n' | { IFS=: read a b; :; }; printf 'e f\\n' | { read x y; printf '[%s][%s]\\n' \"$x\" \"$y\"; } )") ())
```
---
    [e][f]
