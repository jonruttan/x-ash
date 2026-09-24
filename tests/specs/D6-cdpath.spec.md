## sh-eval `cd` looks for its operand in CDPATH

An operand whose first component is not `/`, `.` or `..` is looked for under
each directory CDPATH names, in order, before it is taken as it stands; an
empty entry stands for the working directory.  When a named entry finds it, cd
writes the directory it arrived in, as `cd -` does.  An operand no entry holds
stands as written, and with CDPATH unset nothing is searched or written.

Expectations match `/bin/sh` and `dash` where they agree.  They part on two
corners, and ash follows dash and POSIX on both: bash 3.2 refuses an operand
no entry holds where POSIX takes the operand as written, and after `cd -P` it
writes the path as spelled where POSIX writes the new working directory, the
resolved one.  The third, fourth and last cases are pins that hold on main
too.

### an operand found under a CDPATH entry wins over the working directory, and cd writes it

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir -p \"$d/p/q\" \"$d/w/q\"; cd \"$d/w\"; CDPATH=$d/p; x=$(cd q); cd q >/dev/null; printf '%s|%s\\n' \"${x#$d}\" \"${PWD#$d}\"; cd /; rm -rf \"$d\" )") ())
```
---
    /p/q|/p/q

### an empty entry is the working directory, and cd writes nothing for it

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir -p \"$d/p/q\" \"$d/p/r\" \"$d/w/q\"; cd \"$d/w\"; CDPATH=:$d/p; x=$(cd q); cd q; a=${PWD#$d}; cd \"$d/w\"; y=$(cd r); printf '[%s]|%s|%s\\n' \"$x\" \"$a\" \"${y#$d}\"; cd /; rm -rf \"$d\" )") ())
```
---
    []|/w/q|/p/r

### an operand no entry holds stands as written

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir -p \"$d/p\" \"$d/w/only\"; cd \"$d/w\"; CDPATH=$d/p; cd only; echo \"${PWD#$d}\"; cd /; rm -rf \"$d\" )") ())
```
---
    /w/only

### an operand starting with `./` is not looked for

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir -p \"$d/p/q\" \"$d/w/q\"; cd \"$d/w\"; CDPATH=$d/p; x=$(cd ./q); cd ./q; printf '[%s]|%s\\n' \"$x\" \"${PWD#$d}\"; cd /; rm -rf \"$d\" )") ())
```
---
    []|/w/q

### a relative entry is read from the working directory, and a missing one is passed by

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir -p \"$d/p/q\"; cd \"$d\"; CDPATH=$d/none:p; cd q >/dev/null; echo \"${PWD#$d}\"; cd /; rm -rf \"$d\" )") ())
```
---
    /p/q

### after `cd -P` it writes the resolved directory

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir -p \"$d/p/t\" \"$d/w\"; ln -s \"$d/p/t\" \"$d/p/lnk\"; cd \"$d/w\"; CDPATH=$d/p; x=$(cd -P lnk); case $x in */p/t) echo resolved;; *) echo \"[$x]\";; esac; cd /; rm -rf \"$d\" )") ())
```
---
    resolved

### with CDPATH unset nothing is searched or written

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir -p \"$d/w/q\"; cd \"$d/w\"; unset CDPATH; x=$(cd q); echo \"[$x]\"; cd /; rm -rf \"$d\" )") ())
```
---
    []
