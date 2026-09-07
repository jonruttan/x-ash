## sh-eval eval

`eval` joins its words with a space and reads the result back as shell input,
in THIS shell -- an assignment sticks, and `eval "exit 3"` exits.  The words
have already been expanded once by the time they arrive, so evaluating them
is a second pass, which is the whole point of the builtin.

Each expectation was taken from `/bin/sh` first.

### it reads its argument as shell input

```sh
(do (sh-eval "eval 'echo hi'") ())
```
---
    hi

### its words are joined by a space first

```sh
(do (sh-eval "eval echo a b") ())
```
---
    a b

### it runs in THIS shell, so an assignment sticks

```sh
(do (sh-eval "eval \"v=1\"; echo \"$v\"") ())
```
---
    1

### with nothing to read it succeeds

```sh
(do (sh-eval "eval; echo $?") ())
```
---
    0

### and an empty argument is nothing to read

```sh
(do (sh-eval "eval ''; echo $?") ())
```
---
    0

### the status is the status of what it ran

```sh
(do (sh-eval "eval 'false'; echo $?") ())
```
---
    1

### its argument is expanded once BEFORE it, and once by it

```sh
(do (sh-eval "a=b; b=c; eval \"echo \\$$a\"") ())
```
---
    c

### quoting inside the text is the text's own

```sh
(do (sh-eval "eval 'echo \"a b\"'") ())
```
---
    a b

### a compound command reads as one

```sh
(do (sh-eval "eval 'for i in 1 2; do echo $i; done'") ())
```
---
    2

### eval inside an eval

```sh
(do (sh-eval "eval \"eval \\\"echo deep\\\"\"") ())
```
---
    deep

### the text is a fresh top level, not the enclosing construct's

```sh
(do (sh-eval "if true; then eval 'echo done'; fi") ())
```
---
    done

### and inside a loop just the same

```sh
(do (sh-eval "for i in 1; do eval 'echo in-loop'; done") ())
```
---
    in-loop

### an assignment from inside a function reaches the shell

```sh
(do (sh-eval "f() { eval \"w=inner\"; }; f; echo \"$w\"") ())
```
---
    inner
