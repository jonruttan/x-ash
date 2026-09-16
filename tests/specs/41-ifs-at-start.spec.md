## sh-eval IFS at start

A shell starts with IFS set to space, tab and newline, whatever its
environment held.  POSIX lets a shell ignore an inherited IFS, and `dash` and
bash both do.  So `$IFS` has a value to save, and the usual way to split on
something else for a while --

    old=$IFS; IFS=:; ...; IFS=$old

-- puts ordinary splitting back afterwards rather than turning it off.

Expectations match `/bin/sh` and `dash`.  Every case in a file shares one
shell, so each case that changes IFS sets it back before it ends.

### it holds three characters

```sh
(do (sh-eval "echo \"[${#IFS}]\"") ())
```
---
    [3]

### space, tab and newline

```sh
(do (sh-eval "case $IFS in \" \t\n\") echo \"[exact]\";; *) echo \"[other]\";; esac") ())
```
---
    [exact]

### it is set

```sh
(do (sh-eval "echo \"[${IFS+set}]\"") ())
```
---
    [set]

### saving and restoring it keeps splitting

```sh
(do (sh-eval "old=$IFS; IFS=:; IFS=$old; x=\"a b\"; set -- $x; echo \"[$#]\"") ())
```
---
    [2]

### unset, it splits as the default does

```sh
(do (sh-eval "unset IFS; x=\"a b\"; set -- $x; n=$#; IFS=\" \t\n\"; echo \"[$n]\"") ())
```
---
    [2]

### empty, it does not split

```sh
(do (sh-eval "IFS=; x=\"a b\"; set -- $x; n=$#; IFS=\" \t\n\"; echo \"[$n]\"") ())
```
---
    [1]
