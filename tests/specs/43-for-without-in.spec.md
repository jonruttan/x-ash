## sh-eval for without in

A `for` with no `in` list loops over the positional parameters: `for i; do` is
`for i in "$@"; do`.  Each parameter is one iteration, as it stands -- spaces
and wildcards included -- and the list is the one in place when the loop
starts, so a `set --` in the body does not change it.  The separator before
`do` may be a `;`, a newline, or nothing.

An `in` with no words after it loops no times.

Expectations match `/bin/sh` and `dash`.

### the parameters, in order

```sh
(do (sh-eval "set -- a b; for i; do printf %s \"$i\"; done; echo \"|\"") ())
```
---
    ab|

### a function's own arguments, spaces kept

```sh
(do (sh-eval "f() { for a; do printf '[%s]' \"$a\"; done; echo \"|\"; }; f x \"y z\"") ())
```
---
    [x][y z]|

### with nothing before do

```sh
(do (sh-eval "set -- p q; for i do printf %s \"$i\"; done; echo \"|\"") ())
```
---
    pq|

### with a newline before do

```sh
(do (sh-eval "set -- m n; for i\ndo printf %s \"$i\"; done; echo \"|\"") ())
```
---
    mn|

### wildcards and spaces are not expanded again

```sh
(do (sh-eval "set -- 'a*' 'b c'; for i; do printf '<%s>' \"$i\"; done; echo \"|\"") ())
```
---
    <a*><b c>|

### set -- in the body leaves the loop's list alone

```sh
(do (sh-eval "set -- 1 2; for i; do set -- 9; printf %s \"$i\"; done; echo \"|\"") ())
```
---
    12|

### no parameters, no iterations

```sh
(do (sh-eval "set --; for i; do printf x; done; echo \"|\"") ())
```
---
    |

### an in with no words loops no times

```sh
(do (sh-eval "set -- u v; for i in; do printf x; done; echo \"|\"") ())
```
---
    |

