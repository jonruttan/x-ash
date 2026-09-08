## sh-eval trap

`trap ACTION CONDITION...` says what to do when a condition arrives.  The two
kinds of condition are not equally answerable:

  * **EXIT** (or `0`) is implemented, and it is what scripts overwhelmingly
    use trap for -- remove the temp file however the script ends.
  * **A SIGNAL cannot carry an action.**  The platform's own contract says so
    (`lib/x/sys/posix.x` on `(Sys signal)`): only *ignore* and *default* can
    be installed, because an x-lang closure cannot be a C signal handler.  So
    `trap '' INT` and `trap - INT` are real, and an action on a signal is
    REFUSED with a diagnostic -- accepting it would leave a script looking
    protected when it is not.

Every case runs inside a subshell.  A spec file is one shell process, so an
EXIT trap set at the top level of a case would outlive it and fire on the
harness itself.

Each expectation was taken from `/bin/sh` first.

### an EXIT action runs when the shell leaves

```sh
(do (sh-eval "( trap 'echo bye' EXIT; echo body )") ())
```
---
    bye

### it runs on an explicit exit, and does not change its status

```sh
(do (sh-eval "( trap 'echo bye' EXIT; exit 3 ); echo $?") ())
```
---
    3

### 0 names the same condition as EXIT

```sh
(do (sh-eval "( trap 'echo cleanup' 0; echo run )") ())
```
---
    cleanup

### - removes it

```sh
(do (sh-eval "( trap 'echo no' EXIT; trap - EXIT; echo none )") ())
```
---
    none

### setting it again replaces it

```sh
(do (sh-eval "( trap 'echo a' EXIT; trap 'echo b' EXIT; echo once )") ())
```
---
    b

### with no arguments it prints what is set, in the form that sets it

```sh
(do (sh-eval "( trap 'echo t' EXIT; trap; echo after )") ())
```
---
    t

### a subshell does not inherit it

```sh
(do (sh-eval "( trap 'echo T' EXIT; ( echo sub ); echo main )") ())
```
---
    T

### an exit inside the action chooses the status

```sh
(do (sh-eval "( trap 'echo n; exit 9' EXIT; exit 1 ); echo $?") ())
```
---
    9

### the empty action ignores a signal

```sh
(do (sh-eval "( trap '' INT; echo ignored ); echo $?") ())
```
---
    0

### - restores a signal's default

```sh
(do (sh-eval "( trap - INT; echo restored ); echo $?") ())
```
---
    0

### an ACTION on a signal is refused rather than silently never run

```sh
(do (sh-eval "( trap 'echo x' INT ) 2>/dev/null; echo $?") ())
```
---
    1

### a condition it does not know is refused

```sh
(do (sh-eval "( trap 'echo x' NOSUCHSIG ) 2>/dev/null; echo $?") ())
```
---
    1
