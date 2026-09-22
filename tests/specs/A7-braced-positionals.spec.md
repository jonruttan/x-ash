## sh-eval a positional parameter in braces

In braces a positional parameter's number is every digit up to the operator,
so `${10:-x}` asks about the tenth parameter; unbraced, `$10` is still `$1`
and a `0`.  A number is decimal, leading zeros and all.  An operator that
would assign a positional parameter is refused, as it is in dash: only a
variable can be assigned that way.

Expectations match `/bin/sh` and `dash`, less the refusal's wording, where
they differ: those cases keep the parameter's name from dash's message, which
is ash's.

### the value operators past nine

```sh
(do (sh-eval "( set -- a b c d e f g h i j k; echo \"${10:-x} ${12:-y} ${11%k}. ${10+s}[${12+s}]\" )") ())
```
---
    j y . s[]

### a number is decimal

```sh
(do (sh-eval "( set -- a b c d e f g h i j k; echo \"[${012}]\" \"${09:-z}\" )") ())
```
---
    [] i

### the length and the plain form

```sh
(do (sh-eval "( set -- a b c d e f g h i j k; echo \"${#10} ${10}x ${1}0\" )") ())
```
---
    1 jx a0

### assigning a positional parameter is refused

```sh
(do (sh-eval "( set --; echo \"${1:=x}\"; echo \"after $1\" ) 2>&1 | sed 's/^.*: \\([^:]*\\): .*$/\\1/' | tr '\\n' '|'; echo") ())
```
---
    1|

### past nine as well

```sh
(do (sh-eval "( set -- a b c d e f g h i j k; echo \"${12:=q}\"; echo after ) 2>&1 | sed 's/^.*: \\([^:]*\\): .*$/\\1/' | tr '\\n' '|'; echo") ())
```
---
    12|

### an operator that does not fire assigns nothing, so refuses nothing

```sh
(do (sh-eval "( set -- a; echo \"${1:=x}\" \"${?:=x}\"; unset zz; echo \"${zz:=v}\" \"$zz\" ) 2>&1 | tr '\\n' '|'; echo") ())
```
---
    a 0|v v|
