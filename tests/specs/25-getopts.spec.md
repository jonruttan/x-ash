## sh-eval getopts

`getopts OPTSTRING NAME [ARG...]` reads ONE option per call, driven by a loop:

    while getopts "ab:c" opt; do
      case $opt in a) ...;; b) use "$OPTARG";; esac
    done
    shift $((OPTIND - 1))

Two things carry between calls: OPTIND, the index of the next argument, which
is a shell variable a script may reset; and an offset INSIDE the current
argument, because `-abc` is three options in one word.  The offset is private,
and is reset whenever OPTIND is not what this builtin last wrote -- which is
how a script's `OPTIND=1` is noticed.

Every case runs in a subshell so OPTIND cannot leak between them, and every
expectation was taken from `/bin/sh` first.

### it reads options in turn, and reports where the arguments start

```sh
(do (sh-eval "p() { while getopts \"ab:c\" o; do printf '%s,' \"$o\"; done; printf 'OPTIND=%s\\n' \"$OPTIND\"; }; ( set -- -a -b val -c x y; p \"$@\" )") ())
```
---
    a,b,c,OPTIND=5

### an option's argument may be the next word

```sh
(do (sh-eval "( set -- -b val; while getopts \"b:\" o; do printf '[%s]\\n' \"$OPTARG\"; done )") ())
```
---
    [val]

### or attached to it

```sh
(do (sh-eval "( set -- -bval; while getopts \"b:\" o; do printf '[%s]\\n' \"$OPTARG\"; done )") ())
```
---
    [val]

### a cluster is several options in one word

```sh
(do (sh-eval "( set -- -abval; while getopts \"ab:\" o; do printf '%s:%s,' \"$o\" \"$OPTARG\"; done; echo )") ())
```
---
    a:,b:val,

### -- ends the options and is stepped over

```sh
(do (sh-eval "( set -- -a -- -b; while getopts \"ab:\" o; do printf '%s,' \"$o\"; done; printf 'OPTIND=%s\\n' \"$OPTIND\" )") ())
```
---
    a,OPTIND=3

### the first word that is not an option ends the run

```sh
(do (sh-eval "( set -- plain -a; while getopts \"a\" o; do printf '%s,' \"$o\"; done; printf 'OPTIND=%s\\n' \"$OPTIND\" )") ())
```
---
    OPTIND=1

### a lone dash is an argument, not an option

```sh
(do (sh-eval "( set -- -a -; while getopts \"a\" o; do printf '%s,' \"$o\"; done; printf 'OPTIND=%s\\n' \"$OPTIND\" )") ())
```
---
    a,OPTIND=2

### an unknown option answers ? and says so

```sh
(do (sh-eval "( set -- -z; while getopts \"a\" o 2>/dev/null; do printf '[%s][%s]\\n' \"$o\" \"$OPTARG\"; done )") ())
```
---
    [?][]

### a silent optstring reports the letter in OPTARG instead

```sh
(do (sh-eval "( set -- -z; while getopts \":a\" o; do printf '[%s][%s]\\n' \"$o\" \"$OPTARG\"; done )") ())
```
---
    [?][z]

### and a missing argument answers : under a silent optstring

```sh
(do (sh-eval "( set -- -b; while getopts \":b:\" o; do printf '[%s][%s]\\n' \"$o\" \"$OPTARG\"; done )") ())
```
---
    [:][b]

### an option that looks like one is still taken as an argument

```sh
(do (sh-eval "( set -- -b -a; while getopts \"ab:\" o; do printf '[%s][%s]\\n' \"$o\" \"$OPTARG\"; done )") ())
```
---
    [b][-a]

### arguments may be given instead of the positional parameters

```sh
(do (sh-eval "( getopts \"a\" v -a; printf '%s,OPTIND=%s\\n' \"$v\" \"$OPTIND\" )") ())
```
---
    a,OPTIND=2

### resetting OPTIND starts again

```sh
(do (sh-eval "p() { while getopts \"ac\" o; do printf '%s,' \"$o\"; done; }; ( set -- -a; p \"$@\"; OPTIND=1; set -- -c; p \"$@\"; echo )") ())
```
---
    a,c,
