## sh-eval closing a descriptor

`n>&-` and `n<&-` close descriptor n.  With `exec` the close lasts; on a
command it lasts for that command, as any redirection does, and a subshell's
close stays in the subshell.  Closing a descriptor that is not open is no
failure.

Expectations match `/bin/sh` and `dash` but for a write to a descriptor that
is closed, which fails with 2 here, as in dash, where bash answers 1.

### exec closes one for good

```sh
(do (sh-eval "( exec 3>&1; echo to3 >&3; exec 3>&-; echo after )") ())
```
---
    after

### closing one that is not open is fine

```sh
(do (sh-eval "( exec 3>&-; echo \"s=$?\" )") ())
```
---
    s=0

### so is closing an input one

```sh
(do (sh-eval "( exec 4<&-; echo \"s=$?\" )") ())
```
---
    s=0

### a write to a closed descriptor fails

```sh
(do (sh-eval "( exec 3>&1; exec 3>&-; { echo x >&3; } 2>/dev/null; echo \"s=$?\" )") ())
```
---
    s=2

### a command runs with its stderr closed

```sh
(do (sh-eval "( echo ok 2>&-; echo \"s=$?\" )") ())
```
---
    s=0

### and the close is that command's alone

```sh
(do (sh-eval "( echo ok 2>&-; echo after >&2 ) 2>&1") ())
```
---
    after

### a group's too, and the pipe still carries its stdout

```sh
(do (sh-eval "( { echo a; echo b >&2; } 2>&- | cat; echo \"s=$?\" )") ())
```
---
    s=0

### a function's

```sh
(do (sh-eval "( f() { echo inf >&3; }; exec 3>&1; f 3>&- 2>/dev/null; echo \"s=$?\" )") ())
```
---
    s=2

### a read from a closed stdin finds nothing

```sh
(do (sh-eval "( read v <&- 2>/dev/null; echo \"s=$?\" )") ())
```
---
    s=1

### and a subshell's close is the subshell's

```sh
(do (sh-eval "( exec 3>&1; (exec 3>&-); echo still >&3 )") ())
```
---
    still
