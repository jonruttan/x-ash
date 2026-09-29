## sh-eval compound commands in a loop read into nodes

A for loop is read once, where the evaluator meets it, as a while or until
loop is, and the ifs, cases and groups in any loop's body are read with the
loop: each construct's words -- `then`, `elif`, `else`, `fi`, `in`, `;;`,
`esac`, `}` -- are found once however often the loop goes round.  A construct
whose walks read otherwise is walked over its tokens as before.

The first three cases are pins that hold on main too; their expectations match
`dash` and `/bin/sh`.  The last fails on main.

### for loops: words, parameters, `break` and `continue`

```sh
(do (sh-eval "( for i in a b; do echo $i; done; for i in; do echo never; done; echo st=$?; set -- p q; for i; do echo $i; done; for i in 1 2 3; do [ $i = 2 ] && continue; echo $i; done; for i in 1 2; do for j in a b; do [ $j = b ] && continue 2; echo $i$j; done; done; for i in 1 2; do false; done; echo st=$? ) | tr '\\n' ','; echo") ())
```
---
    a,b,st=0,p,q,1,3,1a,2a,st=1,

### if, case and groups in a loop's body

```sh
(do (sh-eval "( i=0; while [ $i -lt 4 ]; do i=$((i+1)); if [ $i = 1 ]; then echo one; elif [ $i = 2 ]; then echo two; else { echo g$i; }; fi; case $i in 3) echo three;; 4|5) echo four; esac; done ) | tr '\\n' ','; echo") ())
```
---
    one,two,g3,three,g4,four,

### the status each answers, and `set -e`

```sh
(do (sh-eval "( for i in 1; do if false; then :; fi; echo st=$?; case x in y) :;; esac; echo st=$?; { false; }; echo st=$?; done; set -e; for i in 1 2; do if false; then :; fi; case x in y) :;; esac; done; echo alive; for i in 1; do false; done; echo dead ) | tr '\\n' ','; echo") ())
```
---
    st=0,st=0,st=1,alive,

### a loop's compound commands are read once however often it goes round

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
  (= (count "for g5_i in 1; do if true; then : a; fi; case x in x) : b;; esac; { : c; }; done")
     (count "for g5_i in 1 2 3; do if true; then : a; fi; case x in x) : b;; esac; { : c; }; done")))
```
---
    #t
