## sh-eval read

`read [-r] VAR...` takes one line from standard input and splits it on IFS
across the names, with the last name taking everything left, separators and
all.

Without `-r` a backslash quotes the character after it: the backslash goes
away, the character loses any meaning as a delimiter, and a backslash ending
a line joins the next one.  With `-r` a backslash is ordinary data, which is
what `while read -r line` needs.

The status is non-zero at end of input, including for a final line that
arrives without a terminator; the line is still assigned.

The cases print with `printf` rather than `echo`, because `echo` interprets
escape sequences of its own and would report on that instead.

### the last name takes the rest of the line

```sh
(do (sh-eval "printf 'a b c\\n' | { read x y; printf '[%s][%s]\\n' \"$x\" \"$y\"; }") ())
```
---
    [a][b c]

### -r reads the same fields

```sh
(do (sh-eval "printf 'a b c\\n' | { read -r x y; printf '[%s][%s]\\n' \"$x\" \"$y\"; }") ())
```
---
    [a][b c]

### -r keeps a backslash

```sh
(do (sh-eval "printf '%s\\n' 'a\\b' | { read -r v; printf '[%s]\\n' \"$v\"; }") ())
```
---
    [a\b]

### without -r a backslash quotes the next character

```sh
(do (sh-eval "printf '%s\\n' 'a\\b' | { read v; printf '[%s]\\n' \"$v\"; }") ())
```
---
    [ab]

### a backslash quotes a separator, so the field does not end there

```sh
(do (sh-eval "printf '%s\\n' 'a\\ b' | { read v; printf '[%s]\\n' \"$v\"; }") ())
```
---
    [a b]

### a line ending in a backslash continues onto the next

```sh
(do (sh-eval "{ printf '%s\\n' 'one\\'; printf '%s\\n' two; } | { read v; printf '[%s]\\n' \"$v\"; }") ())
```
---
    [onetwo]

### with -r it does not

```sh
(do (sh-eval "{ printf '%s\\n' 'one\\'; printf '%s\\n' two; } | { read -r v; printf '[%s]\\n' \"$v\"; }") ())
```
---
    [one\]

### surrounding whitespace is not part of the value

```sh
(do (sh-eval "printf '  pad  \\n' | { read v; printf '[%s]\\n' \"$v\"; }") ())
```
---
    [pad]

### IFS says what a separator is

```sh
(do (sh-eval "printf 'p:q\\n' | ( IFS=:; read a b; printf '[%s][%s]\\n' \"$a\" \"$b\" )") ())
```
---
    [p][q]

### a name with no field left is empty

```sh
(do (sh-eval "printf 'only\\n' | { read x y; printf '[%s][%s]\\n' \"$x\" \"$y\"; }") ())
```
---
    [only][]

### end of input answers non-zero

```sh
(do (sh-eval "printf '' | { read v; printf '[%s]\\n' \"$?\"; }") ())
```
---
    [1]

### a final line with no terminator is assigned, and still answers non-zero

```sh
(do (sh-eval "printf 'nonl' | { read v; s=$?; printf '[%s][%s]\\n' \"$v\" \"$s\"; }") ())
```
---
    [nonl][1]

### an option this shell does not have is refused

```sh
(do (sh-eval "printf 'x\\n' | { read -q v 2>/dev/null; printf '[%s]\\n' \"$?\"; }") ())
```
---
    [2]
