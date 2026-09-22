## sh-eval `${...}` that is no expansion

What `${...}` holds is a parameter, and then an operator or nothing at all.
Anything else -- `${1a}`, `${a b}`, a `#` length of something that is no
parameter, or no parameter at all -- is refused, where ash read the whole of
it as a name the shell had never been given and answered the empty string.

The refusal ends the command, so the `after` in each case is not reached.  The
two shells word the message differently and exit differently, 1 and 2, so the
cases show neither: each runs in a subshell whose standard error is dropped,
and prints what came out of it.

Expectations match `/bin/sh` and `dash`.

### a name that is no name

```sh
(do (sh-eval "( echo before; echo \"${1a}\"; echo after ) 2>/dev/null | tr '\\n' '|'; echo") ())
```
---
    before|

### a space between two of them

```sh
(do (sh-eval "( echo before; echo \"${a b}\"; echo after ) 2>/dev/null | tr '\\n' '|'; echo") ())
```
---
    before|

### no parameter at all

```sh
(do (sh-eval "( echo before; echo \"${}\"; echo after ) 2>/dev/null | tr '\\n' '|'; echo") ())
```
---
    before|

### an operator with no parameter in front of it

```sh
(do (sh-eval "( echo before; echo \"${:-x}\"; echo after ) 2>/dev/null | tr '\\n' '|'; echo") ())
```
---
    before|

### a length of something that is no parameter

```sh
(do (sh-eval "( echo before; echo \"${#x y}\"; echo after ) 2>/dev/null | tr '\\n' '|'; echo") ())
```
---
    before|

### the expansions that are still expansions

```sh
(do (sh-eval "( x=abc; set -- p q; echo \"[${x}][${x%}][${x?}][${x+}][${x#a}][${x:-z}]\" )") ())
```
---
    [abc][abc][abc][][bc][abc]

### and the ones that count

```sh
(do (sh-eval "( x=abc; set -- p q; echo \"[${#}][${##}][${#x}][${2}][${#:-w}]\" )") ())
```
---
    [2][1][3][q][2]
