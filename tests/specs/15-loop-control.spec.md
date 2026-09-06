## sh-eval break

### break leaves the loop

```sh
(do (sh-eval "out=; for i in 1 2 3; do if [ $i = 2 ]; then break; fi; out=$out$i; done; echo out=$out") ())
```
---
    out=1

### break answers status 0 even after a failing command

```sh
(sh-eval "for i in 1; do false; break; done")
```
---
    0

### break in a while loop

```sh
(do (sh-eval "i=0; while true; do i=$((i+1)); [ $i -ge 3 ] && break; done; echo i=$i") ())
```
---
    i=3

### break in an until loop

```sh
(do (sh-eval "i=0; until false; do i=$((i+1)); [ $i -ge 2 ] && break; done; echo i=$i") ())
```
---
    i=2

### break 2 leaves both loops

```sh
(do (sh-eval "out=; for i in 1 2; do for j in a b; do out=$out$i$j; break 2; done; out=${out}X; done; echo $out") ())
```
---
    1a

### a count deeper than the nesting leaves every loop

```sh
(do (sh-eval "out=; for i in 1 2; do out=$out$i; break 5; done; echo $out-out") ())
```
---
    1-out

### break inside a function leaves the caller's loop

```sh
(do (sh-eval "f() { break; }; out=; for i in 1 2; do f; out=$out$i; done; echo out=$out") ())
```
---
    out=

### break outside a loop is a silent no-op

```sh
(do (sh-eval "break; echo after=$?") ())
```
---
    after=0

### a count below one is out of range and leaves the loop with status 1

```sh
(do (sh-eval "for i in 1 2; do break 0; echo not; done; echo st=$?") ())
```
---
    st=1

## sh-eval continue

### continue skips the rest of the body

```sh
(do (sh-eval "out=; for i in 1 2 3; do if [ $i = 2 ]; then continue; fi; out=$out$i; done; echo $out") ())
```
---
    13

### continue in a while loop

```sh
(do (sh-eval "i=0; out=; while [ $i -lt 3 ]; do i=$((i+1)); continue; out=$out$i; done; echo i=$i,out=$out") ())
```
---
    i=3,out=

### continue in an until loop

```sh
(do (sh-eval "i=0; until [ $i -ge 3 ]; do i=$((i+1)); continue; echo not; done; echo i=$i") ())
```
---
    i=3

### continue 2 resumes the outer loop

```sh
(do (sh-eval "out=; for i in 1 2; do for j in a b; do out=$out$i$j; continue 2; done; out=${out}X; done; echo $out") ())
```
---
    1a2a

### continue on the last iteration ends the loop cleanly

```sh
(do (sh-eval "for i in 1 2; do continue; done; echo after") ())
```
---
    after

### continue inside a function resumes the caller's loop

```sh
(do (sh-eval "f() { continue; }; out=; for i in 1 2 3; do f; out=$out$i; done; echo out=$out") ())
```
---
    out=

### return from inside a loop still leaves the function

```sh
(do (sh-eval "f() { for i in 1 2 3; do return 7; done; echo not; }; f; echo st=$?") ())
```
---
    st=7
