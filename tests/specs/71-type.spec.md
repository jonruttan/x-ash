## sh-eval type

`type NAME...` says what each name is, the way `command -V` says it: a shell
builtin, a shell keyword, a shell function, or the file on PATH that would
run.  A name found nowhere is reported on standard error, and the status is 1
when any name was.  POSIX gives `type` no options, so a word that starts with
`-` is a name like any other.

Expectations match `/bin/sh` and `dash` but where the two disagree with each
other:

  - a function is `NAME is a shell function`, as in dash; bash prints the
    function's body after its own first line
  - a name found nowhere answers 1, as in bash for one name; dash answers 127
  - that report goes to standard error, as in bash; dash writes it to
    standard output among the answers
  - with several names, any found nowhere makes the status 1, as POSIX has
    it; bash answers the last name's status alone
  - an argument that starts with `-` is a name, as in dash; bash reads options

### a builtin

```sh
(do (sh-eval "type cd") ())
```
---
    cd is a shell builtin

### a reserved word

```sh
(do (sh-eval "type if") ())
```
---
    if is a shell keyword

### a function

```sh
(do (sh-eval "( f() { :; }; type f )") ())
```
---
    f is a shell function

### a program on PATH

```sh
(do (sh-eval "d=$(mktemp -d); printf '#!/bin/sh\\n' > \"$d/mycmd\"; chmod +x \"$d/mycmd\"; PATH=\"$d:$PATH\"; [ \"$(type mycmd)\" = \"mycmd is $d/mycmd\" ] && echo found; rm -rf \"$d\"") ())
```
---
    found

### several names, each on its own line

```sh
(do (sh-eval "type cd if | tr '\\n' '|'; echo") ())
```
---
    cd is a shell builtin|if is a shell keyword|

### a name found nowhere answers 1

```sh
(do (sh-eval "type nosuchthing 2>/dev/null; echo \"s=$?\"") ())
```
---
    s=1

### and says so on standard error

```sh
(do (sh-eval "type nosuchthing 2>&1 >/dev/null | grep -c 'nosuchthing: not found'") ())
```
---
    1

### one missing among several still answers 1

```sh
(do (sh-eval "type cd nosuchthing if >/dev/null 2>&1; echo \"s=$?\"") ())
```
---
    s=1

### the others are still said

```sh
(do (sh-eval "type cd nosuchthing if 2>/dev/null | tr '\\n' '|'; echo") ())
```
---
    cd is a shell builtin|if is a shell keyword|

### with no names it does nothing

```sh
(do (sh-eval "type; echo \"s=$?\"") ())
```
---
    s=0

### a word that starts with - is a name

```sh
(do (sh-eval "type -x 2>/dev/null; echo \"s=$?\"") ())
```
---
    s=1
