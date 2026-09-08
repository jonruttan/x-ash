## sh-eval an assignment's value is not split or globbed

POSIX: the word of a variable assignment "shall be expanded ... without field
splitting or pathname expansion".  ash split it, so

    v=$(echo a b)

set `v` to `a` and then ran `b` as a command -- which makes `v=$(date)`,
`v=$(pwd)` under a path with a space, and `v=$(cat file)` all corrupt.

The flag saying a word is an assignment already existed, for tilde expansion.
It is tightened here from "still in the leading run" to "this word IS an
assignment", which is what both rules actually want.  The last case is the
guard on that tightening: an ordinary word still splits.

Each expectation was taken from `/bin/sh` first.

### a command substitution is one value, not its first word

```sh
(do (sh-eval "v=$(echo a b); echo \"[$v]\"") ())
```
---
    [a b]

### quoting it changes nothing, because it was never split

```sh
(do (sh-eval "w=\"$(echo c d)\"; echo \"[$w]\"") ())
```
---
    [c d]

### leading and trailing spaces survive

```sh
(do (sh-eval "x=$(echo \"  pad  \"); echo \"[$x]\"") ())
```
---
    [  pad  ]

### a literal value with a space survives

```sh
(do (sh-eval "z=\"p q\"; echo \"[$z]\"") ())
```
---
    [p q]

### an empty value is empty

```sh
(do (sh-eval "e=$(true); echo \"[$e]\"") ())
```
---
    []

### IFS does not reach it either

```sh
(do (sh-eval "IFS=:; s=$(echo m:n); echo \"[$s]\"") ())
```
---
    [m:n]

### nor is the value globbed

```sh
(do (sh-eval "IFS=' '; g=$(echo '*'); echo \"[$g]\"") ())
```
---
    [*]

### export takes its arguments as assignments too

```sh
(do (sh-eval "export EV=$(echo x y); echo \"[$EV]\"") ())
```
---
    [x y]

### a word that is NOT in assignment position is still split

```sh
(do (sh-eval "c=\"echo two words\"; $c | tr ' ' ','") ())
```
---
    two,words
