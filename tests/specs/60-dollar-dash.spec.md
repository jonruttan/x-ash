## sh-eval $-

`$-` answers the letters of the options now set, so `case "$-" in *e*)` asks
whether `set -e` is on.  Turning an option off takes its letter out again.

Each case asks whether a letter is there rather than reading the whole string:
which options a shell has beyond POSIX's is the shell's own business, and bash
answers letters dash does not.  Each case leaves the options as it found them.

Expectations match `/bin/sh` and `dash`.

### the letter of an option that is set, and gone once it is not

```sh
(do (sh-eval "set -e; case \"$-\" in *e*) printf \"[e]\";; esac; set +e; case \"$-\" in *e*) printf \"[still]\";; *) printf \"[gone]\";; esac; echo") ())
```
---
    [e][gone]

### one letter for each option set

```sh
(do (sh-eval "set -eu; case \"$-\" in *e*) printf \"[e]\";; esac; case \"$-\" in *u*) printf \"[u]\";; esac; set +eu; echo") ())
```
---
    [e][u]

### the letter of set -f

```sh
(do (sh-eval "set -f; case \"$-\" in *f*) printf \"[f]\";; esac; set +f; echo") ())
```
---
    [f]

### which set -o noglob sets as well

```sh
(do (sh-eval "set -o noglob; case \"$-\" in *f*) printf \"[f]\";; esac; set +o noglob; echo") ())
```
---
    [f]

### and of set -x

```sh
(do (sh-eval "set -x 2>/dev/null; case \"$-\" in *x*) printf \"[x]\";; esac; set +x 2>/dev/null; echo") ())
```
---
    [x]

### ${-} is the same parameter

```sh
(do (sh-eval "set -e; case \"${-}\" in *e*) printf \"[brace]\";; esac; set +e; echo") ())
```
---
    [brace]

### with the options off, none of their letters is there

```sh
(do (sh-eval "set +efux; case \"$-\" in *[efux]*) printf \"[some]\";; *) printf \"[none]\";; esac; echo") ())
```
---
    [none]
