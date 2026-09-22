## sh-eval `set -u` and every kind of parameter

With `set -u`, expanding a parameter that is unset is an error: a name, in
braces or not, and its length; a positional parameter past the last; `$!`
before any list has run in the background.  The expansion that asks about
set-ness -- `${X:-w}`, `${X-w}`, `${X+w}`, `${X:+w}` -- never is, and nor are
`$@` and `$*`.

Expectations match `/bin/sh` and `dash`, less the start of the message, where
they differ: each case keeps what follows the last `: `, which is dash's
wording and ash's.  An error ends the subshell, so `after` is not reached.

### a positional parameter past the last

```sh
(do (sh-eval "( set -u; set -- a; echo \"$1\"; echo \"$2\"; echo after ) 2>&1 | sed 's/^.*: //' | tr '\\n' '|'; echo") ())
```
---
    a|parameter not set|

### a name in braces

```sh
(do (sh-eval "( set -u; echo \"${zz}\"; echo after ) 2>&1 | sed 's/^.*: //' | tr '\\n' '|'; echo") ())
```
---
    parameter not set|

### the length of one

```sh
(do (sh-eval "( set -u; echo \"${#zz}\"; echo after ) 2>&1 | sed 's/^.*: //' | tr '\\n' '|'; echo") ())
```
---
    parameter not set|

### a positional in braces past nine

```sh
(do (sh-eval "( set -u; set -- a; echo \"${10}\"; echo after ) 2>&1 | sed 's/^.*: //' | tr '\\n' '|'; echo") ())
```
---
    parameter not set|

### `$!` before any background list

```sh
(do (sh-eval "( set -u; echo \"$!\"; echo after ) 2>&1 | sed 's/^.*: //' | tr '\\n' '|'; echo") ())
```
---
    parameter not set|

### and what `$!` is to the value operators until then

```sh
(do (sh-eval "( echo \"[${!-x}] [${!+s}]\" )") ())
```
---
    [x] []

### the operators that ask are no error

```sh
(do (sh-eval "( set -u; echo \"${zz:-d} ${zz-d} [${zz+s}] [${zz:+s}]\"; echo after ) 2>&1 | tr '\\n' '|'; echo") ())
```
---
    d d [] []|after|

### nor are `$@` and `$*` with no parameters

```sh
(do (sh-eval "( set -u; set --; echo \"[$@]\" \"[$*]\"; echo after ) 2>&1 | tr '\\n' '|'; echo") ())
```
---
    [] []|after|

### nor a parameter set to nothing

```sh
(do (sh-eval "( set -u; zz=; echo \"[$zz][${zz}][${#zz}]\"; echo after ) 2>&1 | tr '\\n' '|'; echo") ())
```
---
    [][][0]|after|
