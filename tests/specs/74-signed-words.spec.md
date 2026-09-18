## sh-eval a word with a sign is the word it is spelt as

A word that opens with `-` or `+` and goes on in digits -- `-0`, `+5`,
`-007` -- is an ordinary word, passed as it is written.  The tokenizer base's
own number reader would take it for an integer and give back `0`, `5` and
`-7`; `kill -0 $pid`, the usual question of whether a process is running,
became `kill 0 $pid`, which signals the caller's whole process group.

These cases write the arguments out rather than send any signal, so that a
return of the old reading fails here instead of stopping the suite.

Expectations match `/bin/sh` and `dash`.

### a minus zero

```sh
(do (sh-eval "printf '[%s]' -0; echo") ())
```
---
    [-0]

### a plus sign

```sh
(do (sh-eval "printf '[%s]' +5; echo") ())
```
---
    [+5]

### leading zeros after a sign

```sh
(do (sh-eval "printf '[%s]' -007 -00; echo") ())
```
---
    [-007][-00]

### and without one, as before

```sh
(do (sh-eval "printf '[%s]' 007 00 -5; echo") ())
```
---
    [007][00][-5]

### an option is still a word

```sh
(do (sh-eval "printf '[%s]' -a --x - +; echo") ())
```
---
    [-a][--x][-][+]

### a sign ahead of an expansion

```sh
(do (sh-eval "y=Y; printf '[%s]' -$y +\"$y\"; echo") ())
```
---
    [-Y][+Y]

### ahead of a quote

```sh
(do (sh-eval "printf '[%s]' -'q' +\"1 2\"; echo") ())
```
---
    [-q][+1 2]

### a signed run that turns into letters

```sh
(do (sh-eval "printf '[%s]' +1a -2b; echo") ())
```
---
    [+1a][-2b]

### arithmetic still reads a sign as a sign

```sh
(do (sh-eval "echo $((-5 + +3)) $(( -0 ))") ())
```
---
    -2 0

### and so does test

```sh
(do (sh-eval "[ -5 -lt 0 ] && [ +3 -eq 3 ] && echo signed") ())
```
---
    signed

### a function sees the word it was given

```sh
(do (sh-eval "f() { printf '[%s]' \"$@\"; echo; }; f -0 +0") ())
```
---
    [-0][+0]
