## sh-eval redirections undone inside one another

A builtin's, a function call's and a compound command's redirections are
undone when they finish, and they nest: `echo x >&2` inside a function whose
call sends stdout and stderr elsewhere moves a descriptor the call has
already moved.  Each puts back exactly what it changed, innermost first, so
the shell's own descriptors are what they were once the outermost is done.
A pipeline moves the shell's stdin while its last stage runs, and puts it
back the same way.

Expectations match `/bin/sh` and `dash`.

### a group sending a builtin's >&2 away

```sh
(do (sh-eval "( { echo b >&2; } >/dev/null 2>&1; echo after )") ())
```
---
    after

### a function call

```sh
(do (sh-eval "( f() { echo x >&2; }; f >/dev/null 2>&1; echo after )") ())
```
---
    after

### a function logging through another

```sh
(do (sh-eval "( log() { echo \"$*\" >&2; }; main() { log hi; echo body; } >/dev/null 2>&1; main; echo after )") ())
```
---
    after

### a loop

```sh
(do (sh-eval "( for i in 1; do echo x >&2; done >/dev/null 2>&1; echo after )") ())
```
---
    after

### the same descriptor moved at both levels

```sh
(do (sh-eval "( { echo in 1>&2; } 1>/dev/null; echo after ) 2>/dev/null") ())
```
---
    after

### what the inner redirection wrote reaches the outer one's file

```sh
(do (sh-eval "( f=$(mktemp); { echo a; echo b >&2; } 2>\"$f\" >/dev/null; cat \"$f\"; rm -f \"$f\" )") ())
```
---
    b

### a pipeline in a pipeline's last stage gives stdin back

```sh
(do (sh-eval "( f=$(mktemp); printf 'line1\\n' > \"$f\"; ( exec < \"$f\"; echo a | { cat | cat; } >/dev/null; read -r x; echo \"[$x]\" ); rm -f \"$f\" )") ())
```
---
    [line1]
