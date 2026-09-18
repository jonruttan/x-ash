## sh-eval the word of a parameter expansion keeps its quoting

When `${x:-word}` or `${x:+word}` fires, the word stands where the expansion
stood, with the quoting it was written with.  Inside double quotes it is one
string with its own quotes taken off.  Outside them its fields splice into the
word around it: a quoted part is neither split nor globbed, and an unquoted
part -- its literal text as well as what it expands to -- is split on IFS and
globbed, as an expansion's result is.  `=` assigns the word's value and `?`
reports it, quotes and escapes off.

The word is expanded only when the operator fires, and its end is found past
any quoted or escaped brace inside it.

Each case unsets what it expects unset: the suite runs several files in one
shell.  Expectations match `/bin/sh` and `dash`.

### a quoted bracket in the alternate, inside quotes

```sh
(do (sh-eval "( v=x; echo \"${v:+\"[$v]\"}\" )") ())
```
---
    [x]

### and outside them

```sh
(do (sh-eval "( v=x; echo ${v:+\"[$v]\"} )") ())
```
---
    [x]

### a quoted star in a default does not glob

```sh
(do (sh-eval "( unset x; d=$(mktemp -d); cd \"$d\"; : > f; echo ${x:-\"*\"}; cd /; rm -rf \"$d\" )") ())
```
---
    *

### nor inside quotes

```sh
(do (sh-eval "( unset x; echo \"${x:-\"*\"}\" )") ())
```
---
    *

### an escaped brace is part of the word

```sh
(do (sh-eval "( unset x; echo ${x:-\\}} )") ())
```
---
    }

### so is a brace in a quoted part

```sh
(do (sh-eval "( unset x; echo \"${x:-\"}\"}\" )") ())
```
---
    }

### a quoted part stays one field, the rest splits

```sh
(do (sh-eval "( unset x; v='a b'; set -- ${x:-\"$v\" c}; echo \"$#\" )") ())
```
---
    2

### quoting within a part

```sh
(do (sh-eval "( unset x; set -- ${x:-a' 'b c}; echo \"$#:$1\" )") ())
```
---
    2:a b

### the unquoted text splits on IFS

```sh
(do (sh-eval "( unset x; IFS=:; set -- ${x:-a:b}; echo \"$#\" )") ())
```
---
    2

### an escaped space does not

```sh
(do (sh-eval "( unset x; set -- ${x:-a\\ b}; echo \"$#\" )") ())
```
---
    1

### the first field joins what came before, the last what comes after

```sh
(do (sh-eval "( unset x; set -- x${x:-a b}y; echo \"$#:$1:$2\" )") ())
```
---
    2:xa:by

### an empty quoted word is one empty field

```sh
(do (sh-eval "( unset x; set -- ${x:-\"\"}; echo \"$#\" )") ())
```
---
    1

### an empty word is none

```sh
(do (sh-eval "( unset x; set -- ${x:-}; echo \"$#\" )") ())
```
---
    0

### but inside quotes it is one

```sh
(do (sh-eval "( unset x; set -- \"${x:-}\"; echo \"$#\" )") ())
```
---
    1

### in an assignment the word is not split

```sh
(do (sh-eval "( unset x; y=${x:-a b}; echo \"[$y]\" )") ())
```
---
    [a b]

### two in one word

```sh
(do (sh-eval "( unset x; echo \"${x:-a}${x:-b}\" )") ())
```
---
    ab

### a tilde in a default is a home directory

```sh
(do (sh-eval "( unset x; echo ${x:-~} | grep -c '^/' )") ())
```
---
    1

### = assigns the word's value

```sh
(do (sh-eval "( unset x; : ${x:=\"a b\"}; echo \"[$x]\" )") ())
```
---
    [a b]

### ? reports it

```sh
(do (sh-eval "( unset x; (: ${x:?\"no x here\"}) 2>&1 | grep -c 'no x here' )") ())
```
---
    1

### the word is not expanded when the operator does not fire

```sh
(do (sh-eval "( x=set; t=$(mktemp); : ${x:-$(echo side > \"$t\")}; if [ -s \"$t\" ]; then echo ran; else echo skipped; fi; rm -f \"$t\" )") ())
```
---
    skipped
