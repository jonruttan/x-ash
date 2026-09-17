## sh-eval where set -e reaches

Under `set -e`, a command that fails ends the shell, except where its failure
is the point: the condition of an `if`, `elif`, `while` or `until`, a pipeline
that starts with `!`, and every operand of an `&&` or `||` list but the last.
A subshell, a pipeline's stages or a function body run in one of those places
carries the exemption into what it runs.  Run anywhere else, it applies `-e`
itself.

A command substitution is a script of its own: its commands apply `-e`
whatever position the command around it holds.

Each case runs in a subshell, so that the shell `-e` ends is the subshell and
the case can read its status.  Expectations match `/bin/sh` and `dash`.

### a failing command ends a subshell

```sh
(do (sh-eval "( set -e; false; echo after ); echo \"[$?]\"") ())
```
---
    [1]

### the last operand of a list ends it too

```sh
(do (sh-eval "( set -e; true && false; echo after ); echo \"[$?]\"") ())
```
---
    [1]

### an operand that is not the last does not

```sh
(do (sh-eval "( set -e; false && true; echo \"[end]\" )") ())
```
---
    [end]

### nor does a while condition

```sh
(do (sh-eval "( set -e; while false; do :; done; echo \"[end]\" )") ())
```
---
    [end]

### a pipeline under ! does not, whatever its status

```sh
(do (sh-eval "( set -e; ! true; echo \"[end]\" )") ())
```
---
    [end]

### a subshell that fails ends the subshell around it

```sh
(do (sh-eval "( set -e; ( ( false; echo inner ); echo mid ); echo outer ); echo \"[$?]\"") ())
```
---
    [1]

### a function body applies -e

```sh
(do (sh-eval "( set -e; f() { false; echo in; }; f; echo after ); echo \"[$?]\"") ())
```
---
    [1]

### so does a for body

```sh
(do (sh-eval "( set -e; for i in 1; do false; echo in; done; echo after ); echo \"[$?]\"") ())
```
---
    [1]

### and a brace group

```sh
(do (sh-eval "( set -e; { false; echo in; }; echo after ); echo \"[$?]\"") ())
```
---
    [1]

### a pipeline's stages apply it

```sh
(do (sh-eval "( set -e; { false; printf in; } | cat; echo \"[end]\" )") ())
```
---
    [end]

### a subshell as an if condition runs without it

```sh
(do (sh-eval "( set -e; if ( false; printf in ); then printf yes; fi; echo \"[end]\" )") ())
```
---
    inyes[end]

### so does a function called as one

```sh
(do (sh-eval "( set -e; f() { false; printf in; }; if f; then printf yes; fi; echo \"[end]\" )") ())
```
---
    inyes[end]

### and a subshell as a while condition

```sh
(do (sh-eval "( set -e; while ( false; printf in; exit 1 ); do :; done; echo \"[end]\" )") ())
```
---
    in[end]

### a subshell on the left of && runs without it

```sh
(do (sh-eval "( set -e; ( false; printf in ) && printf and; echo \"[end]\" )") ())
```
---
    inand[end]

### and on the left of ||

```sh
(do (sh-eval "( set -e; ( false; printf in ) || printf or; echo \"[end]\" )") ())
```
---
    in[end]

### and under !

```sh
(do (sh-eval "( set -e; ! ( false; printf in ); echo \"[end]\" )") ())
```
---
    in[end]

### a function called on the left of ||

```sh
(do (sh-eval "( set -e; f() { false; printf in; }; f || true; echo \"[end]\" )") ())
```
---
    in[end]

### an operand pipeline's stages run without it

```sh
(do (sh-eval "( set -e; { false; printf in; } | cat || true; echo \"[end]\" )") ())
```
---
    in[end]

### a command substitution applies it

```sh
(do (sh-eval "( set -e; v=$(false; echo in) || true; echo \"[$v]\" )") ())
```
---
    []

### even as an if condition

```sh
(do (sh-eval "( set -e; if v=$(false; echo in); then echo \"t[$v]\"; else echo \"e[$v]\"; fi )") ())
```
---
    e[]

### and decides operands afresh inside

```sh
(do (sh-eval "( set -e; v=$( ( false; printf in ) && printf and ); echo \"[$v]\" )") ())
```
---
    [inand]

### an assignment whose substitution fails ends the subshell

```sh
(do (sh-eval "( set -e; x=$(false); echo after ); echo \"[$?]\"") ())
```
---
    [1]

