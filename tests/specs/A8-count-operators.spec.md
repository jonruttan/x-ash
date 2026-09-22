## sh-eval `${#...}`: a length, or an operator on the count

`${#X}` is the length of X when X is one parameter and nothing more:
`${##}` is the length of the count, `${#?}` of the last status.  When an
operator follows the `#` instead, the `#` is the parameter count and the
operator applies to it, as it would to any parameter: `${#:-x}` is the count,
`${##1}` the count with a leading `1` trimmed.

Expectations match `/bin/sh` and `dash`.

### an operator on the count

```sh
(do (sh-eval "( set -- a b c d e f g h i j k l; echo \"[${#:-x}] [${#-x}] [${#+p}]\" )") ())
```
---
    [12] [12] [p]

### a trim of it

```sh
(do (sh-eval "( set -- a b c d e f g h i j k l; echo \"[${##1}] [${#%2}]\" )") ())
```
---
    [2] [1]

### with no parameters the count is set, to 0

```sh
(do (sh-eval "( set --; echo \"[${#:-x}] [${#:+p}]\" )") ())
```
---
    [0] [p]

### the length of one parameter

```sh
(do (sh-eval "( set -- a b c d e f g h i j k l; x=hello; echo \"[${##}] [${#?}] [${#x}] [${#10}] [${#}]\" )") ())
```
---
    [2] [1] [5] [1] [12]
