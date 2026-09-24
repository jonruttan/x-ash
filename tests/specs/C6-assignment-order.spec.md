## sh-eval the order of a command's assignments

POSIX 2.9.1 expands a simple command's words other than its assignments
first, then expands and makes each assignment in turn.  So an assignment sees
the ones before it -- `v=1 w=$v`, `x=5 x=$((x+1))`, `HOME=/g y=~/c` -- the
command's arguments see none of them, and a command substitution in an
argument runs before one in an assignment.  An assignment is known by its
raw token, before anything is expanded: a word that only expands to
NAME=value is a command's name.

Expectations match `/bin/sh` and `dash`.  The last two cases are pins that
hold on main too.

### each assignment sees the ones before it, and the arguments none

```sh
(do (sh-eval "( a=0; a=1 echo \"[$a]\"; v=1 w=$v; echo \"[$v$w]\"; unset v w; v=1 w=$v /usr/bin/env | grep \"^w=\"; x=5 x=$((x+1)); echo \"x=$x\"; y=1 y=$y$y : ; echo \"y=$y\" ) | tr '\\n' ','; echo") ())
```
---
    [0],[11],w=1,x=6,y=11,

### the arguments' substitutions run first

```sh
(do (sh-eval "( a=$(echo A >&2) true $(echo B >&2) ) 2>&1 | tr '\\n' ','; echo") ())
```
---
    B,A,

### a function's prefix assignments

```sh
(do (sh-eval "( f() { echo \"f:$p$q\"; }; p=1 q=$p f ) | tr '\\n' ','; echo") ())
```
---
    f:11,

### a word that expands to NAME=value is a command

```sh
(do (sh-eval "( x='a=1'; $x 2>/dev/null; echo \"st=$? a=[$a]\" ) | tr '\\n' ','; echo") ())
```
---
    st=127 a=[],

### a tilde after the `=`, and quoting kept

```sh
(do (sh-eval "( HOME=/h; x=~/a:~/b; echo \"$x\"; HOME=/g y=~/c; echo \"$y\"; x=\"a b\" y='$x' z=$(echo \"p  q\"); echo \"$x|$y|$z\" ) | tr '\\n' ','; echo") ())
```
---
    /h/a:/h/b,/g/c,a b|$x|p  q,

### the status of a command with no command name

```sh
(do (sh-eval "( v=$(false); echo \"s=$?\"; v=$(exit 3) w=1; echo \"s=$?\"; true; x=1 y=$(exit 4) z=2; echo \"s=$? $x$z\" ) | tr '\\n' ','; echo") ())
```
---
    s=1,s=3,s=4 12,

### an assignment's value is one field

```sh
(do (sh-eval "( v='p q'; w=$v; echo \"[$w]\"; w=$v; set -- $w; echo $# ) | tr '\\n' ','; echo") ())
```
---
    [p q],2,
