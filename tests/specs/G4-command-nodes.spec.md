## sh-eval a loop read into nodes

A while or until loop is read once, where the evaluator meets it, into nodes:
its condition and body, and the lists, and-or lists and pipelines in them.  So
where each command ends, whether `&&`, `||` or `&` follows it, and where the
loop's `do` and `done` stand are found once however often the loop goes round.
A loop whose walks read otherwise -- malformed input -- is walked over its
tokens as before, so its errors come where they always did.

The first three cases are pins that hold on main too; their expectations match
`dash` and `/bin/sh`.  The fourth pins this shell's own errors, and holds on
main too.  The last fails on main.

### lists, and-or lists, `!` and `&` in a loop's body

```sh
(do (sh-eval "( n=0; while [ $n -lt 1 ]; do n=1; echo a; true && echo t1 || echo t2; false && echo f1 || echo f2; ! true; echo $?; ! false && echo n1 || echo n2; true &&
echo split; echo bg & wait; done ) | tr '\\n' ','; echo") ())
```
---
    a,t1,f2,1,n1,split,bg,

### loops, `break` and `continue`, and the status a loop answers

```sh
(do (sh-eval "( i=0; while [ $i -lt 5 ]; do i=$((i+1)); [ $i = 2 ] && continue; [ $i = 4 ] && break; echo $i; done; echo st=$?; i=0; while true; do i=$((i+1)); j=0; while true; do j=$((j+1)); [ $j = 2 ] && continue 2; [ $i = 3 ] && break 2; echo $i$j; done; done; i=0; until [ $i -ge 2 ]; do i=$((i+1)); false; done; echo st=$?; while false; do :; done; echo st=$? ) | tr '\\n' ','; echo") ())
```
---
    1,3,st=0,11,21,st=1,st=0,

### `set -e` in and-or lists and loops

```sh
(do (sh-eval "( set -e; i=0; while [ $i -lt 2 ]; do i=$((i+1)); false || true; done; while false; do :; done; echo alive; i=0; while [ $i -lt 3 ]; do i=$((i+1)); [ $i = 2 ] && false; echo $i; done ) | tr '\\n' ','; echo") ())
```
---
    alive,1,

### a loop that reads otherwise fails where it always did

```sh
(do (sh-eval "( while false; do echo x; fi; echo after ) 2>&1 | tr '\\n' ','; ( while false; echo x; done ) 2>&1 | tr '\\n' ','; echo") ())
```
---
    ash: parse error: unexpected EOF in while,x,ash: parse error: expected do,

### a loop's commands are read once however often it goes round

The walk that finds where a command's stage ends is made as often going round
three times as going round once.

```sh
(let ((saved %sh-stage-end)
      (walks 0))
  (def count
    (fn (_ text)
      (set! walks 0)
      (set! %sh-stage-end
        (fn (_ ts wdepth pdepth)
          (set! walks (+ walks 1))
          (saved ts wdepth pdepth)))
      (guard (e (do (set! %sh-stage-end saved) (error e))) (sh-eval text))
      (set! %sh-stage-end saved)
      walks))
  (= (count "g4_i=0; while [ $g4_i -lt 1 ]; do g4_i=$((g4_i+1)); : a; done")
     (count "g4_i=0; while [ $g4_i -lt 3 ]; do g4_i=$((g4_i+1)); : a; done")))
```
---
    #t
