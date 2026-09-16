## sh-eval the status of a command with no command name

A command whose words are all assignments, or whose words expand to nothing,
has no command name.  Its status is the exit status of the last command
substitution it performed, or 0 when it performed none (POSIX 2.9.1).  That is
what makes `if out=$(cmd); then` test `cmd`, and `out=$(cmd) || exit` leave
when `cmd` fails.

A command that has a command name has that command's status, whatever its
words substituted.

Expectations match `/bin/sh` and `dash`.

### an assignment takes its substitution's status

```sh
(do (sh-eval "v=$(false); echo \"[$?]\"") ())
```
---
    [1]

### whatever that status is

```sh
(do (sh-eval "v=$(exit 3); echo \"[$?]\"") ())
```
---
    [3]

### the last substitution decides

```sh
(do (sh-eval "v=$(false)$(true); echo \"[$?]\"") ())
```
---
    [0]

### whichever of them it is

```sh
(do (sh-eval "v=$(true)$(false); echo \"[$?]\"") ())
```
---
    [1]

### an assignment with no substitution succeeds

```sh
(do (sh-eval "false; v=x; echo \"[$?]\"") ())
```
---
    [0]

### a later plain assignment does not reset it

```sh
(do (sh-eval "v=$(false) w=1; echo \"[$?]\"") ())
```
---
    [1]

### a command name's status is the command's

```sh
(do (sh-eval "v=$(exit 4) true; echo \"[$?]\"") ())
```
---
    [0]

### words that expand to nothing name no command

```sh
(do (sh-eval "$(exit 5); echo \"[$?]\"") ())
```
---
    [5]

### backquotes count the same

```sh
(do (sh-eval "false; v=`false`; echo \"[$?]\"") ())
```
---
    [1]

### so an if on an assignment tests the substitution

```sh
(do (sh-eval "if v=$(false); then echo \"[then]\"; else echo \"[else]\"; fi") ())
```
---
    [else]

### and || after one runs its right side

```sh
(do (sh-eval "v=$(false) || echo \"[or]\"") ())
```
---
    [or]

### a function's status inside the substitution

```sh
(do (sh-eval "f() { return 6; }; v=$(f); echo \"[$?]\"") ())
```
---
    [6]

### a quoted substitution counts

```sh
(do (sh-eval "v=\"$(exit 7)\"; echo \"[$?]\"") ())
```
---
    [7]

### so does one inside a parameter expansion

```sh
(do (sh-eval "v=${u:-$(exit 8)}; echo \"[$?]\"") ())
```
---
    [8]

### export is a command name

```sh
(do (sh-eval "false; export ASH_Q=$(exit 9); echo \"[$?]\"") ())
```
---
    [0]

### arithmetic is not a substitution

```sh
(do (sh-eval "v=$((1+1)); echo \"[$?]\"") ())
```
---
    [0]

