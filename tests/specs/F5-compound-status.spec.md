## sh-eval the status of a compound command

A loop answers the status of the last command its body ran, or 0 when its body
never ran; the condition that ends it is not its status (POSIX, and ash's
evalloop and evalfor).  `break` and `continue` answer 0.

`set -e` judges the commands in a compound's body.  A compound alone in its
pipeline -- an if, a case, a loop, a group -- ends nothing by its own status,
as in ash's evaltree; a subshell's status is checked, and so are a
pipeline's and a function call's.

Expectations match `dash` and `/bin/sh`.  The second and fifth cases hold on
main too.

### a loop answers its body's last status

```sh
(do (sh-eval "( for x in a b; do [ $x = a ]; done; echo $?; i=0; while [ $i -lt 1 ]; do i=1; false; done; echo $?; i=0; until [ $i -ge 1 ]; do i=1; false; done; echo $?; for x in a; do (exit 3); done; echo $? ) | tr '\\n' ','; echo") ())
```
---
    1,1,1,3,

### a loop that never ran, or ended by break or continue, answers 0

```sh
(do (sh-eval "( for x in; do false; done; echo $?; false; while false; do :; done; echo $?; for x in a b; do false; break; done; echo $?; for x in a b; do false; continue; done; echo $? ) | tr '\\n' ','; echo") ())
```
---
    0,0,0,0,

### a loop's failure is an operand's

```sh
(do (sh-eval "( for x in a; do false; done || echo failed; while :; do false; break; done && echo broke ) | tr '\\n' ','; echo") ())
```
---
    failed,broke,

### set -e leaves an if, a group, a case and a loop to their commands

```sh
(do (sh-eval "( set -e; if true; then ! true; fi; echo $?; { ! true; }; echo $?; case a in a) ! true;; esac; echo $?; for x in a; do ! true; done; echo $? ) | tr '\\n' ','; echo") ())
```
---
    1,1,1,1,

### set -e ends at a failing subshell, pipeline and function call

```sh
(do (sh-eval "( ( set -e; (false); echo no ); echo sub $?; ( set -e; true | false; echo no ); echo pipe $?; ( set -e; f() { ! true; }; f; echo no ); echo fn $? ) | tr '\\n' ','; echo") ())
```
---
    sub 1,pipe 1,fn 1,
