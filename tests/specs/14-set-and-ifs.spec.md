## sh-eval set -- and positional parameters

### set -- replaces the positional parameters

```sh
(do (sh-eval "set -- a b c; echo $# [$1] [$3]") ())
```
---
    3 [a] [c]

### $@ joins them

```sh
(do (sh-eval "set -- a b; echo [$@]") ())
```
---
    [a b]

### a bare set -- clears them

```sh
(do (sh-eval "set -- a b; set --; echo [$#]") ())
```
---
    [0]

### set operands without -- set them too

```sh
(do (sh-eval "set x y; echo $#") ())
```
---
    2

### shift still applies

```sh
(do (sh-eval "set -- a b c; shift; echo [$@]") ())
```
---
    [b c]

## sh-eval IFS

### the default splits on whitespace

```sh
(do (sh-eval "n() { echo $#; }; X=\"a b  c\"; n $X") ())
```
---
    3

### a single-character IFS splits on it

```sh
(do (sh-eval "n() { echo $#; }; IFS=:; X=a:b:c; n $X") ())
```
---
    3

### a non-whitespace IFS keeps empty fields

```sh
(do (sh-eval "n() { echo $#; }; IFS=:; X=a::b; n $X") ())
```
---
    3

### whitespace runs collapse to one delimiter

```sh
(do (sh-eval "n() { echo $#; }; IFS=\" \"; X=\"a   b\"; n $X") ())
```
---
    2

### an empty IFS suppresses splitting

```sh
(do (sh-eval "n() { echo $#; }; IFS=; X=\"p q r\"; n $X") ())
```
---
    1

### IFS applies to a command substitution too

```sh
(do (sh-eval "n() { echo $#; }; IFS=:; n $(echo a:b:c)") ())
```
---
    3

### quoting still defeats splitting whatever IFS is

```sh
(do (sh-eval "n() { echo $#; }; IFS=:; X=a:b; n \"$X\"") ())
```
---
    1

## sh-eval set -x

### xtrace does not change the output

```sh
(do (sh-eval "set +x; echo traced") ())
```
---
    traced

### and can be turned back off

```sh
(do (sh-eval "set -x; set +x; echo -n after") (newline))
```
---
    after

## sh-eval set -u

### an unset parameter is an error

```sh
(write (guard (e (lit raised)) (sh-eval "set -u; echo $NOSUCHVAR_ASH")))
```
---
    raised

### a set parameter is fine

```sh
(do (sh-eval "set -u; X=v; echo $X") ())
```
---
    v

### a default still works, which is what it is for

```sh
(do (sh-eval "set -u; echo ${NOSUCHVAR_ASH:-dflt}") ())
```
---
    dflt

### set +u turns it off again

```sh
(do (sh-eval "set -u; set +u; echo [$NOSUCHVAR_ASH]") ())
```
---
    []

## sh-eval set -e

`set -e` must NOT fire where a command's failure is the point — POSIX exempts
a condition, either operand of an AND-OR list but the last, and `!`. Each of
these would end the shell if it did.

### a false condition does not exit

```sh
(do (sh-eval "set -e; if false; then echo no; fi; echo -n survived") (newline))
```
---
    survived

### a failing left side of || does not exit

```sh
(do (sh-eval "set -e; false || echo -n survived") (newline))
```
---
    survived

### a failing left side of && does not exit

```sh
(do (sh-eval "set -e; false && echo no; echo -n survived") (newline))
```
---
    survived

### a negated failure does not exit

```sh
(do (sh-eval "set -e; ! false; echo -n survived") (newline))
```
---
    survived

### a while condition does not exit

```sh
(do (sh-eval "set -e; while false; do echo no; done; echo -n survived") (newline))
```
---
    survived

### and set +e turns it off

```sh
(do (sh-eval "set -e; set +e; false; echo -n survived") (newline))
```
---
    survived

## sh-eval short-circuit consumes the operand it skips

Recursive descent skips the EVALUATION, not the tokens. The cursor was left on
the skipped operand, so %eval-list found a command where it expected a
separator, gave up, and silently discarded the rest of the script. Pre-existing
since 2024 and invisible whenever nothing followed on the same line.

### a skipped && operand does not eat what follows

```sh
(do (sh-eval "false && echo no; echo after") ())
```
---
    after

### nor does a skipped || operand

```sh
(do (sh-eval "true || echo no; echo after") ())
```
---
    after

### the alternative after a skipped && still runs

```sh
(do (sh-eval "false && echo a || echo b") ())
```
---
    b

### and after a skipped ||

```sh
(do (sh-eval "true || echo a && echo b") ())
```
---
    b

### skipping crosses a pipeline

```sh
(do (sh-eval "false && echo a | grep a; echo after") ())
```
---
    after

### skipping crosses a compound

```sh
(do (sh-eval "false && if true; then echo a; fi; echo after") ())
```
---
    after

### skipping crosses a subshell

```sh
(do (sh-eval "false && (echo a); echo after") ())
```
---
    after

### and a nested one

```sh
(do (sh-eval "false && (echo a; (echo b)); echo after") ())
```
---
    after

### a short-circuit inside a subshell does not eat the subshell

```sh
(do (sh-eval "(false && echo a; echo inner)") ())
```
---
    inner

### a taken branch still runs

```sh
(do (sh-eval "true && echo -n yes; echo :after") ())
```
---
    yes:after
