## sh-eval a function before a builtin

A command name is looked for as POSIX orders it: a special builtin, then a
function, then any other builtin, then a file on PATH.  So a function can
wrap a builtin of its own name, reaching the builtin with `command`.  `type`
says what would run in the same order.

Expectations match `/bin/sh` and `dash` but for `type`, which says
`NAME is a shell function` as in dash; bash prints the function's body after
its own first line.

### a function beats a builtin

```sh
(do (sh-eval "( echo() { printf 'X%s\\n' \"$*\"; }; echo hi )") ())
```
---
    Xhi

### command reaches the builtin

```sh
(do (sh-eval "( echo() { printf 'X%s\\n' \"$*\"; }; command echo hi )") ())
```
---
    hi

### a function wraps the builtin of its name

```sh
(do (sh-eval "( cd() { command cd \"$@\" && echo \"in $PWD\"; }; cd / )") ())
```
---
    in /

### test

```sh
(do (sh-eval "( test() { echo mine; }; test -n x )") ())
```
---
    mine

### pwd

```sh
(do (sh-eval "( pwd() { echo fake; }; pwd )") ())
```
---
    fake

### read

```sh
(do (sh-eval "( read() { echo own-read; }; read x )") ())
```
---
    own-read

### true

```sh
(do (sh-eval "( true() { echo not-builtin; }; true )") ())
```
---
    not-builtin

### type says what runs

```sh
(do (sh-eval "( echo() { :; }; type echo )") ())
```
---
    echo is a shell function
