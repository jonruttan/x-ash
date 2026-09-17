## sh-eval command

`command NAME [arg...]` runs NAME as though no function had that name, and
`command -v NAME` answers what would be run instead of running it: a builtin
or a function or a reserved word as written, a name holding a `/` as written,
and anything else as the first file on PATH that could be executed.  `-V` says
what the name is rather than what would run, and the last of `-v` and `-V` is
the one that answers.

POSIX's `-p`, which would run the name under a PATH of the implementation's
choosing, is refused rather than ignored: a script asking for a trusted PATH
must not be handed the untrusted one instead.

Expectations match `/bin/sh` and `dash` but for three, where the reference
shells disagree with each other:

  - a name that is found nowhere answers 1, as in bash; dash answers 127
  - `-V` of a function says `NAME is a shell function`, as in dash; bash
    prints the function's body after that line
  - a file on PATH without an execute bit is passed over, as in bash; dash
    answers it
  - `-V -v` answers as the `-v` written last, as in bash; dash keeps the `-V`
    whichever came last

### -v finds a program on PATH

```sh
(do (sh-eval "d=$(mktemp -d); printf '#!/bin/sh\\n' > \"$d/mycmd\"; chmod +x \"$d/mycmd\"; PATH=\"$d:$PATH\"; [ \"$(command -v mycmd)\" = \"$d/mycmd\" ] && echo found; rm -rf \"$d\"") ())
```
---
    found

### and passes over a file it could not run

```sh
(do (sh-eval "d=$(mktemp -d); : > \"$d/mycmd\"; PATH=\"$d:$PATH\"; command -v mycmd; echo \"s=$?\"; rm -rf \"$d\"") ())
```
---
    s=1

### -v answers a builtin with its own name

```sh
(do (sh-eval "command -v cd") ())
```
---
    cd

### a function with its own name

```sh
(do (sh-eval "( f() { echo fn; }; command -v f )") ())
```
---
    f

### and a reserved word with its own

```sh
(do (sh-eval "command -v if") ())
```
---
    if

### a name that is found nowhere answers 1

```sh
(do (sh-eval "command -v nosuchthing; echo \"s=$?\"") ())
```
---
    s=1

### a name holding a slash stands for itself

```sh
(do (sh-eval "d=$(mktemp -d); printf '#!/bin/sh\\n' > \"$d/mycmd\"; chmod +x \"$d/mycmd\"; [ \"$(command -v \"$d/mycmd\")\" = \"$d/mycmd\" ] && echo found; rm -rf \"$d\"") ())
```
---
    found

### unless there is nothing there

```sh
(do (sh-eval "command -v ./nosuchthing; echo \"s=$?\"") ())
```
---
    s=1

### -V says what the name is

```sh
(do (sh-eval "command -V cd") ())
```
---
    cd is a shell builtin

### for a reserved word

```sh
(do (sh-eval "command -V if") ())
```
---
    if is a shell keyword

### for a function

```sh
(do (sh-eval "( f() { :; }; command -V f )") ())
```
---
    f is a shell function

### and for a program, with the path that would run

```sh
(do (sh-eval "case \"$(command -V ls)\" in ls\\ is\\ /*/ls) echo ok;; *) echo no;; esac") ())
```
---
    ok

### options may be written together

```sh
(do (sh-eval "command -vV cd") ())
```
---
    cd is a shell builtin

### and the last of -v and -V is the one that answers

```sh
(do (sh-eval "command -V -v cd") ())
```
---
    cd

### it runs past a function of the same name

```sh
(do (sh-eval "( ls() { echo shadow; }; command ls /dev/null )") ())
```
---
    /dev/null

### and finds no function of its own

```sh
(do (sh-eval "( f() { echo fn; }; command f 2>/dev/null; echo \"s=$?\" )") ())
```
---
    s=127

### -- ends the options

```sh
(do (sh-eval "command -- ls /dev/null") ())
```
---
    /dev/null

### an unknown option is refused

```sh
(do (sh-eval "command -x ls 2>/dev/null; echo \"s=$?\"") ())
```
---
    s=2

### with no arguments at all it does nothing

```sh
(do (sh-eval "command; echo \"s=$?\"") ())
```
---
    s=0
