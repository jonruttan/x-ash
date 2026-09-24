## sh-eval a command with no command name makes its redirections

A command with no command name -- redirections alone, or with assignments --
still makes its redirections, as POSIX 2.9.1 has it: `> f` creates or empties
f, `>> f` creates it, and nothing it opens stays open after.  The redirections
come before the assignments, so one that cannot be made fails the command with
status 2 and no assignment made, and under `set -e` that ends the shell.  A
command substitution in a redirection's word does not give the command its
status.

Expectations match `dash`.  `/bin/sh`, bash 3.2, agrees on all but the
failures: it answers 1 for them and makes the assignment anyway.  The last two
cases are pins that hold on main too, where nothing was opened at all.

### a redirection alone creates its file, and each of two is made

```sh
(do (sh-eval "( d=$(mktemp -d); > \"$d/new\"; >> \"$d/app\"; > \"$d/1\" > \"$d/2\"; for f in new app 1 2; do [ -f \"$d/$f\" ] && printf '%s,' \"$f\"; done; rm -rf \"$d\" ); echo") ())
```
---
    new,app,1,2,

### `>` alone empties a file

```sh
(do (sh-eval "( d=$(mktemp -d); echo keep > \"$d/k\"; > \"$d/k\"; wc -c < \"$d/k\" | tr -d ' '; rm -rf \"$d\" )") ())
```
---
    0

### an assignment beside a redirection is made, and so is the redirection

```sh
(do (sh-eval "( d=$(mktemp -d); x=1 > \"$d/f\"; [ -f \"$d/f\" ] && echo \"made x=$x\"; rm -rf \"$d\" )") ())
```
---
    made x=1

### a redirection that cannot be made fails the command before its assignment

```sh
(do (sh-eval "( x=0; x=2 > /nonexistent/f; echo \"s=$? x=$x\"; < /nonexistent/f; echo \"s=$?\" ) 2>/dev/null | tr '\\n' ','; echo") ())
```
---
    s=2 x=0,s=2,

### under `set -e` that failure ends the shell

```sh
(do (sh-eval "( set -e; > /nonexistent/f; echo not-here ) 2>/dev/null; echo \"after s=$?\"") ())
```
---
    after s=2

### inside a command substitution too

```sh
(do (sh-eval "( d=$(mktemp -d); v=$(> \"$d/c\"; echo out); [ -f \"$d/c\" ] && echo \"c-made $v\"; rm -rf \"$d\" )") ())
```
---
    c-made out

### a descriptor it opens does not stay open

```sh
(do (sh-eval "( d=$(mktemp -d); 4> \"$d/p\"; { echo x >&4; } 2>/dev/null; echo \"s=$?\"; rm -rf \"$d\" )") ())
```
---
    s=2

### a command substitution in its word does not give the status

```sh
(do (sh-eval "( d=$(mktemp -d); > \"$(false; echo \"$d/g\")\"; echo \"s=$?\"; rm -rf \"$d\" )") ())
```
---
    s=0
