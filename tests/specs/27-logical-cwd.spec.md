## sh-eval the working directory is a path, not an inode

`cd` folds `.` and `..` in its operand by text rather than by following
symlinks, and `pwd` reports the route the shell took.  On a system where
`/tmp` is a symlink to `/private/tmp`, `cd /tmp` then `pwd` answers `/tmp`,
and `cd ..` from there reaches `/`.

`cd` also maintains `PWD` and `OLDPWD`, and `cd -` returns to `OLDPWD` and
writes the directory it arrived at.

Expectations match both `/bin/sh` and `dash`.  The cases use `/tmp`, which is
a symlink on macOS and a real directory on Linux; each states the answer that
holds either way.

### pwd reports the path as given, not as resolved

```sh
(do (sh-eval "cd /; cd /tmp; pwd") ())
```
---
    /tmp

### PWD carries the same path

```sh
(do (sh-eval "cd /; cd /tmp; echo \"$PWD\"") ())
```
---
    /tmp

### .. is folded by text, so it does not follow the link

```sh
(do (sh-eval "cd /; cd /tmp; cd ..; pwd") ())
```
---
    /

### .. crosses several components at once

```sh
(do (sh-eval "cd /usr/bin; cd ../lib; pwd") ())
```
---
    /usr/lib

### . changes nothing

```sh
(do (sh-eval "cd /usr; cd .; pwd") ())
```
---
    /usr

### .. at the root stays at the root

```sh
(do (sh-eval "cd /; cd ..; pwd") ())
```
---
    /

### cd records where it came from

```sh
(do (sh-eval "cd /usr; cd /; echo \"$OLDPWD\"") ())
```
---
    /usr

### cd - returns there and says so

```sh
(do (sh-eval "cd /usr; cd /; cd -") ())
```
---
    /usr

### cd - with nothing to return to is an error

```sh
(do (sh-eval "( unset OLDPWD; cd - 2>/dev/null; echo $? )") ())
```
---
    1

### assigning to PWD does not move the shell

```sh
(do (sh-eval "cd /usr; PWD=/wrong; pwd") ())
```
---
    /usr

### a failed cd leaves the directory alone

```sh
(do (sh-eval "cd /usr; cd /nosuchdir 2>/dev/null; pwd") ())
```
---
    /usr

### a subshell's cd does not move the parent

```sh
(do (sh-eval "cd /; ( cd /usr ); pwd") ())
```
---
    /
