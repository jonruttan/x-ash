## sh-eval { ...; } groups without forking

`{ ...; }` and `( ... )` group commands for the same reasons -- one
redirection over several of them, one stage of a pipeline, one operand of
`&&` -- and differ in exactly one way: the braces run in THIS shell.

    v=1; { v=2; }; echo $v      prints 2
    v=1; ( v=2 );  echo $v      prints 1

So the braces are what a script wants unless it is after the isolation, and
`cmd | { read x; ...; }` is the idiom that needs them -- a `read` in a
subshell sets a variable nobody will ever see.

`{` and `}` are RESERVED WORDS rather than punctuation, which is why the `;`
before `}` is required rather than decorative, and why `echo {` still prints a
brace: a reserved word is only reserved where a command could start.

Each expectation was taken from `/bin/sh` first, and cross-checked against
`dash` wherever the two could differ.

### it runs the commands

```sh
(do (sh-eval "{ echo a; echo b; }") ())
```
---
    b

### an assignment inside it reaches the shell -- this is not a subshell

```sh
(do (sh-eval "v=1; { v=2; }; echo \"[$v]\"") ())
```
---
    [2]

### and so does a cd

`/usr` rather than `/tmp`: on macOS `/tmp` is a symlink to `/private/tmp`, and
this shell reports the physical path where bash reports the logical one.  That
is a real difference, but it is not the one under test here.

```sh
(do (sh-eval "( cd /; { cd /usr; }; pwd )") ())
```
---
    /usr

### it is one stage of a pipeline

```sh
(do (sh-eval "{ echo a; echo b; } | wc -l | tr -d ' '") ())
```
---
    2

### which is what makes read in a pipeline useful

```sh
(do (sh-eval "echo fed | { read x; echo \"[$x]\"; }") ())
```
---
    [fed]

### one redirection covers the whole group

```sh
(do (sh-eval "f=$(mktemp); { echo a; echo b; } > $f; o=$(wc -l < $f | tr -d ' '); rm -f $f; echo \"got=$o\"") ())
```
---
    got=2

### its status is the last command's

```sh
(do (sh-eval "{ true; false; }; echo $?") ())
```
---
    1

### so || sees it

```sh
(do (sh-eval "{ false; } || echo or") ())
```
---
    or

### it nests

```sh
(do (sh-eval "{ { echo deep; }; }") ())
```
---
    deep

### it serves as a condition

```sh
(do (sh-eval "if { true; }; then echo cond; fi") ())
```
---
    cond

### and sits inside a loop body

```sh
(do (sh-eval "for i in 1 2; do { echo n$i; }; done") ())
```
---
    n2

### a brace where a command cannot start is an ordinary word

```sh
(do (sh-eval "echo {") ())
```
---
    {

### a function body is still a function body

```sh
(do (sh-eval "f() { { echo nested; }; }; f") ())
```
---
    nested
