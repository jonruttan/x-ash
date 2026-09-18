## sh-eval an assignment begins with a name

A word is an assignment only when what comes before its first `=` is a NAME:
a letter or underscore, then letters, digits and underscores.  Anything else
ahead of the `=` makes the word an ordinary one, so in command position it is
a command to run -- `a-b=1` is looked for, and not found -- and after a
command's name it is an argument like any other.

Expectations match `/bin/sh` and `dash`, but for the last case, which asks the
test itself.

### a name is assigned

```sh
(do (sh-eval "_ok9=1; echo \"[$_ok9]\"") ())
```
---
    [1]

### a dash before the = makes a command

```sh
(do (sh-eval "a-b=1 2>/dev/null; echo \"s=$?\"") ())
```
---
    s=127

### so does a leading digit

```sh
(do (sh-eval "1x=5 2>/dev/null; echo \"s=$?\"") ())
```
---
    s=127

### and a dot

```sh
(do (sh-eval "x.y=3 2>/dev/null; echo \"s=$?\"") ())
```
---
    s=127

### an empty name is no name

```sh
(do (sh-eval "=1 2>/dev/null; echo \"s=$?\"") ())
```
---
    s=127

### a bad name ahead of a command is the command

```sh
(do (sh-eval "a-b=1 echo hi 2>/dev/null; echo \"s=$?\"") ())
```
---
    s=127

### and the words after it are its arguments

```sh
(do (sh-eval "f() { echo \"n=$#\"; }; g=f; ( \"$g\" a-b=1 x=2 )") ())
```
---
    n=2

### an argument that is not an assignment is split like any other

```sh
(do (sh-eval "v='p q'; set -- a-b=$v; echo \"n=$#\"") ())
```
---
    n=2

### the value after a name keeps its = signs

```sh
(do (sh-eval "a=b=c; echo \"[$a]\"") ())
```
---
    [b=c]

### the test's own answers

```sh
(do (write (map (fn (_ w) (if (%is-assignment? w) 1 0))
  (list "x=1" "_=1" "_x9=1" "X=1" "xY_z=1" "=1" "a-b=1" "1x=5" "x.y=3" "x"
        "x9" "9=1" "a=b=c" "=" "a=" "Z=" "z=" "@=1" "`=1" "{=1")))
  ())
```
---
    (1 1 1 1 1 0 0 0 0 0 0 0 1 0 1 1 1 0 0 0)
