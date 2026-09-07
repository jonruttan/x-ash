## sh-eval redirections on compound commands

`for ... done > log` redirects the whole loop, and the redirection is written
AFTER the construct it applies to.  The parser evaluates as it reads, so it
used to meet that `>` too late -- and `%eval-list` ends its list at any token
it does not recognise, so the redirection was ignored AND every command after
it in the script was silently dropped, with a zero status.

EVERY CASE ENDS IN A MARKER LINE, and that is deliberate.  The suite compares
the last line of output, so a case that merely printed the redirected text
would pass on the broken code too -- the text simply arrived on the terminal
instead of in the file.  Ending with `echo "got=$o"` after reading the file
back makes the truncation visible: on the old code that line never runs.

Each expectation was taken from `/bin/sh` first.

### a subshell's output goes to the file

```sh
(do (sh-eval "f=$(mktemp); ( echo a ) > $f; o=$(cat \"$f\"); rm -f \"$f\"; echo \"got=$o\"") ())
```
---
    got=a

### a for loop redirects the WHOLE loop

```sh
(do (sh-eval "f=$(mktemp); for i in 1 2; do echo x$i; done > $f; o=$(cat \"$f\" | tr \"\\n\" \",\"); rm -f \"$f\"; echo \"got=$o\"") ())
```
---
    got=x1,x2,

### an if redirects its branch

```sh
(do (sh-eval "f=$(mktemp); if true; then echo c; fi > $f; o=$(cat \"$f\"); rm -f \"$f\"; echo \"got=$o\"") ())
```
---
    got=c

### a case redirects its branch

```sh
(do (sh-eval "f=$(mktemp); case x in x) echo e;; esac > $f; o=$(cat \"$f\"); rm -f \"$f\"; echo \"got=$o\"") ())
```
---
    got=e

### appending after a truncating write keeps both

```sh
(do (sh-eval "f=$(mktemp); ( echo one ) > $f; ( echo two ) >> $f; o=$(cat \"$f\" | tr \"\\n\" \",\"); rm -f \"$f\"; echo \"got=$o\"") ())
```
---
    got=one,two,

### a descriptor may be named before the operator

```sh
(do (sh-eval "f=$(mktemp); for i in 1; do echo oops >&2; done 2> $f; o=$(cat \"$f\"); rm -f \"$f\"; echo \"got=$o\"") ())
```
---
    got=oops

### input redirection feeds the construct, and not the shell's own stream

```sh
(do (sh-eval "f=$(mktemp); echo fed > $f; o=$( ( cat ) < $f ); rm -f \"$f\"; echo \"got=$o\"") ())
```
---
    got=fed

### THE COMMANDS AFTER IT STILL RUN -- the silent truncation this fixes

```sh
(do (sh-eval "f=$(mktemp); ( echo a ) > $f; rm -f \"$f\"; echo reached") ())
```
---
    reached

### the construct's status is its own

```sh
(do (sh-eval "( exit 4 ) > /dev/null; echo $?") ())
```
---
    4

### and && sees it

```sh
(do (sh-eval "if true; then echo t; fi > /dev/null && echo chained") ())
```
---
    chained
