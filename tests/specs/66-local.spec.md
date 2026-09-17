## sh-eval local

`local NAME[=VALUE]...` inside a function gives each name a value for the
call and puts the old one back when the call ends -- the value it held,
whether it was exported, and any `readonly` mark given to it inside.  The
scope is dynamic: a function called from this one sees the local.  Outside a
function nothing would ever put the value back, so it is refused.

Expectations match `/bin/sh` and `dash` but for two, where the reference
shells disagree with each other and this follows bash: a name given no value
starts unset, where dash leaves the outer value showing through it; and
`local` outside a function is reported and answers 1, where dash ends the
shell over it.

### the name is the call's

```sh
(do (sh-eval "x=global; f() { local x=1; echo \"in=$x\"; }; f") ())
```
---
    in=1

### and the old value comes back

```sh
(do (sh-eval "x=global; f() { local x=1; }; f; echo \"out=$x\"") ())
```
---
    out=global

### with no value it starts unset

```sh
(do (sh-eval "x=g; f() { local x; echo \"in=[${x-unset}]\"; }; f") ())
```
---
    in=[unset]

### a function called from here sees it

```sh
(do (sh-eval "x=0; g() { echo \"g sees $x\"; }; f() { local x=1; g; }; f") ())
```
---
    g sees 1

### return puts it back

```sh
(do (sh-eval "x=g; f() { local x=1; return; }; f; echo \"out=$x\"") ())
```
---
    out=g

### several names at once

```sh
(do (sh-eval "f() { local x=1 y=2; echo \"$x$y\"; }; f") ())
```
---
    12

### assigning after the declaration assigns the local

```sh
(do (sh-eval "x=g; f() { local x; x=5; }; f; echo \"out=$x\"") ())
```
---
    out=g

### the status is zero

```sh
(do (sh-eval "f() { local x=1; echo \"s=$?\"; }; f") ())
```
---
    s=0

### unsetting the local leaves the outer one

```sh
(do (sh-eval "x=g; f() { local x=1; unset x; }; f; echo \"out=$x\"") ())
```
---
    out=g

### each call has its own

```sh
(do (sh-eval "f() { local n=\"$1\"; if [ \"$n\" -gt 0 ]; then f $((n-1)); fi; printf \"[%s]\" \"$n\"; }; f 2; echo") ())
```
---
    [0][1][2]

### the value is expanded before the name is the call's

```sh
(do (sh-eval "x=g; f() { local x=\"$x-inner\"; echo \"in=$x\"; }; f") ())
```
---
    in=g-inner

### a local that shadows an export reaches a child

```sh
(do (sh-eval "export x=g; f() { local x=1; sh -c 'echo \"child=$x\"'; }; f") ())
```
---
    child=1

### and the export is put back

```sh
(do (sh-eval "export x=g; f() { local x=1; }; f; sh -c 'echo \"env=$x\"'") ())
```
---
    env=g

### a readonly mark ends with the call

```sh
(do (sh-eval "x=g; f() { local x=1; readonly x; }; f; x=set-again; echo \"now=$x\"") ())
```
---
    now=set-again

### a subshell sees it and changes nothing

```sh
(do (sh-eval "x=g; f() { local x=1; ( x=sub ); echo \"back=$x\"; }; f") ())
```
---
    back=1

### outside a function it is refused

```sh
(do (sh-eval "local x=1; echo \"top=$?\"") ())
```
---
    top=1
