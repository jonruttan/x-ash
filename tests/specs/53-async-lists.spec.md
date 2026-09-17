## sh-eval asynchronous lists

An and-or list that ends with `&` runs in a child the shell does not wait for:
the shell carries on at once with status 0, and `$!` is the child's process
id.  The list runs as a subshell does, so what it sets stays in the child, and
its standard input is /dev/null before its own redirections.  `wait` waits for
all of them and answers 0, or for the pids it is given and answers the last
one's status -- 127 for a pid that is not one of this shell's.

Expectations match `/bin/sh` and `dash`.

### the shell carries on before the list finishes

```sh
(do (sh-eval "{ sleep 1; printf \"[late]\"; } & printf \"[early]\"; wait; echo") ())
```
---
    [early][late]

### $! is the child's process id

```sh
(do (sh-eval "sleep 0 & pid=$!; case $pid in *[!0-9]*|\"\") printf \"[bad]\";; *) printf \"[pid]\";; esac; wait; echo") ())
```
---
    [pid]

### and each new list's

```sh
(do (sh-eval "sleep 0 & a=$!; sleep 0 & b=$!; wait; [ \"$a\" != \"$b\" ] && printf \"[new]\"; echo") ())
```
---
    [new]

### wait answers the status of the pid it waited for

```sh
(do (sh-eval "(exit 3) & p=$!; wait $p; printf \"[%s]\" $?; echo") ())
```
---
    [3]

### with no pid it waits for all and answers 0

```sh
(do (sh-eval "false & true & wait; printf \"[%s]\" $?; echo") ())
```
---
    [0]

### a pid that is not this shell's child answers 127

```sh
(do (sh-eval "wait 99999 2>/dev/null; printf \"[%s]\" $?; echo") ())
```
---
    [127]

### the list runs as a subshell

```sh
(do (sh-eval "x=1; x=2 & wait; printf \"[%s]\" \"$x\"; echo") ())
```
---
    [1]

### with /dev/null for its input

```sh
(do (sh-eval "echo input | { cat & wait; printf \"[end]\"; } | tr '\\n' ' '; echo") ())
```
---
    [end]

### the whole and-or list goes to the background

```sh
(do (sh-eval "true && false & wait $!; printf \"[%s]\" $?; echo") ())
```
---
    [1]

### so does a pipeline

```sh
(do (sh-eval "echo x | tr x y & wait") ())
```
---
    y

### and a compound command

```sh
(do (sh-eval "if true; then printf \"[t]\"; fi & wait; printf \"[x]\"; echo") ())
```
---
    [t][x]

### a list in a case clause

```sh
(do (sh-eval "case x in x) { printf \"[c]\"; } & ;; esac; wait; printf \"[after]\"; echo") ())
```
---
    [c][after]

### a function

```sh
(do (sh-eval "f() { return 4; }; f & wait $!; printf \"[%s]\" $?; echo") ())
```
---
    [4]

### a list in a loop body

```sh
(do (sh-eval "for i in 1 2; do printf \"[%s]\" $i & wait; done; echo") ())
```
---
    [1][2]
