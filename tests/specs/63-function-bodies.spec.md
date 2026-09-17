## sh-eval a function body is a compound command

POSIX writes a definition as `fname ( ) compound-command [redirection...]`, so
a body is any compound command: a subshell, a brace group, `if`, `for`,
`while`, `until` or `case`.  What follows the `()` is the rest of that
command, and the `;` inside the body belongs to the body.

The body is kept as tokens and parsed when the function runs, so a redirection
written after it is expanded at the call rather than at the definition.

Expectations match `/bin/sh` and `dash`, except the last: a simple command as
a body is a dash extension that POSIX and bash refuse.

### a subshell body

```sh
(do (sh-eval "f() ( echo sub ); f") ())
```
---
    sub

### whose status is the subshell's

```sh
(do (sh-eval "f() ( exit 3 ); f; echo \"status=$?\"") ())
```
---
    status=3

### and whose cd does not escape

```sh
(do (sh-eval "cd /; f() ( cd /tmp ); f; pwd") ())
```
---
    /

### the call's arguments reach it

```sh
(do (sh-eval "f() ( echo \"got $1\" ); f arg") ())
```
---
    got arg

### an if body

```sh
(do (sh-eval "f() if [ \"$1\" = y ]; then echo yes; else echo no; fi; f y; f n") ())
```
---
    no

### a for body

```sh
(do (sh-eval "f() for i in a b c; do printf \"%s\" \"$i\"; done; f; echo") ())
```
---
    abc

### a while body

```sh
(do (sh-eval "f() while [ \"$1\" -gt 0 ]; do echo tick; set -- 0; done; f 1") ())
```
---
    tick

### an until body

```sh
(do (sh-eval "f() until [ \"$1\" -gt 0 ]; do echo tick; set -- 1; done; f 0") ())
```
---
    tick

### a case body, whose pattern has parens of its own

```sh
(do (sh-eval "f() case \"$1\" in (a) echo first;; *) echo other;; esac; f a; f z") ())
```
---
    other

### a brace group is still a brace group

```sh
(do (sh-eval "f() { echo braced; }; f") ())
```
---
    braced

### and return still unwinds from one

```sh
(do (sh-eval "f() { return 3; }; f; echo \"s=$?\"") ())
```
---
    s=3

### a redirection after the body applies at the call

```sh
(do (sh-eval "f() { echo hidden; } > /dev/null; f; echo after") ())
```
---
    after

### with its target expanded there

```sh
(do (sh-eval "t=$(mktemp); f() ( echo sub ) > \"$1\"; f \"$t\"; o=$(cat \"$t\"); rm -f \"$t\"; echo \"got=$o\"") ())
```
---
    got=sub

### a body may start on the next line

```sh
(do (sh-eval "f()\n(\n  echo lines\n)\nf") ())
```
---
    lines

### a simple command is not a body

```sh
(do (sh-eval "f() echo hi") ())
```
---
    Error: parse error: no compound command after f()
