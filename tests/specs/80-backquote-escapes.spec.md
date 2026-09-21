## sh-eval backslashes inside backquotes

Inside backquotes a backslash keeps its literal meaning, except before `$`, a
backquote or another backslash, where it is taken off before the command in
them runs.  So `` \` `` opens a substitution inside one, `\$` hands a `$` to
the inner command to expand, and `\\` is one backslash.  A backslash before
anything else stays, as it would have been written.

Expectations match `/bin/sh` and `dash`.

### a backquote inside backquotes, escaped

```sh
(do (sh-eval "( x=`echo \\`echo nested\\``; echo \"$x\" )") ())
```
---
    nested

### a dollar passed through to the inner command

```sh
(do (sh-eval "( echo `echo \\$HOME` | grep -c / )") ())
```
---
    1

### a doubled backslash is one

```sh
(do (sh-eval "( v=val; echo `echo \\\\$v` )") ())
```
---
    $v

### nested inside double quotes

```sh
(do (sh-eval "( echo \"`echo \\`echo in-quotes\\``\" )") ())
```
---
    in-quotes

### a backslash before anything else stays

```sh
(do (sh-eval "( echo `echo a\\nb` )") ())
```
---
    anb

### a substitution with no backslash is untouched

```sh
(do (sh-eval "( x=`printf '%s' \"a b\"`; echo \"[$x]\" )") ())
```
---
    [a b]

### three deep

```sh
(do (sh-eval "( x=`echo \\`echo \\\\\\`echo deep\\\\\\`\\``; echo \"$x\" )") ())
```
---
    deep

### the backslash comes off before the inner command is read, quotes and all

```sh
(do (sh-eval "( x=`echo 'a\\$b'`; echo \"$x\" )") ())
```
---
    a$b
