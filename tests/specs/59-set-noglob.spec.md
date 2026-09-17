## sh-eval set -f

`set -f`, also written `set -o noglob`, turns pathname expansion off: a field
that holds a pattern stands as written instead of being matched against the
directory.  `set +f` turns it back on.  Nothing else changes -- a `case`
pattern still matches, since that is not pathname expansion.

Each case makes a directory of its own and works inside a subshell, so the
option and the working directory are its own.

Expectations match `/bin/sh` and `dash`.

### a pattern stands as written, until the option is turned off again

```sh
(do (sh-eval "d=$(mktemp -d); ( cd \"$d\"; : > a1; : > a2; printf \"[%s]\" a*; set -f; printf \"[%s]\" a*; set +f; printf \"[%s]\" a* ); rm -rf \"$d\"; echo") ())
```
---
    [a1][a2][a*][a1][a2]

### set -o noglob names the same option

```sh
(do (sh-eval "d=$(mktemp -d); ( cd \"$d\"; : > b1; set -o noglob; printf \"[%s]\" b*; set +o noglob; printf \"[%s]\" b* ); rm -rf \"$d\"; echo") ())
```
---
    [b*][b1]

### a for list stands as written too

```sh
(do (sh-eval "d=$(mktemp -d); ( cd \"$d\"; : > c1; set -f; for i in c*; do printf \"[%s]\" \"$i\"; done ); rm -rf \"$d\"; echo") ())
```
---
    [c*]

### and a pattern a substitution answers

```sh
(do (sh-eval "d=$(mktemp -d); ( cd \"$d\"; : > g1; set -f; x=$(printf \"%s\" g*); set +f; y=$(printf \"%s\" g*); printf \"[%s][%s]\" \"$x\" \"$y\" ); rm -rf \"$d\"; echo") ())
```
---
    [g*][g1]

### a case pattern still matches, and an assignment keeps its own

```sh
(do (sh-eval "set -f; case h1 in h*) printf \"[match]\";; esac; v=h*; printf \"[%s]\" \"$v\"; set +f; echo") ())
```
---
    [match][h*]

### with the option off, a pattern is matched as before

```sh
(do (sh-eval "d=$(mktemp -d); ( cd \"$d\"; : > k1; : > k2; printf \"[%s]\" k* ); rm -rf \"$d\"; echo") ())
```
---
    [k1][k2]
