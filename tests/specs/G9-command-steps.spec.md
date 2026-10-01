## sh-eval simple commands read into steps, and lists into forms

A simple command in a loop or a function is read once into steps: its words
and redirections in order, each as the walk over its tokens takes it when the
command runs.  A command of assignments alone is read further: each
assignment's name, and its value as a literal, a lone parameter, a lone
arithmetic expansion, or a value word expanded by itself.  An argument that
is one parameter is read as that parameter, its value taken as the field when
nothing in it would split or glob, and one that is an arithmetic expansion
whose expression has nothing to expand is read as the expression's tree,
run when the command runs.  A list is read into a form the evaluator runs.  A command whose tokens
the walk would read otherwise is walked as before.

The expectations match `dash` and `/bin/sh`, save for the wording of ash's own
error messages.

### assignments in loops and functions

```sh
(do (sh-eval "( HOME=/h; unset u; for i in 1 2; do x=$i; y=${i}; z=lit; e=; w=$u; v=1 t=$v; a=~/d; echo \"[$x][$y][$z][$e][$w][$t][$a]\"; done; f() { l=$1; m=\"$l $l\"; echo \"$l|$m\"; }; f a; f b ) | tr '\\n' ','; echo") ())
```
---
    [1][1][lit][][][1][/h/d],[2][2][lit][][][1][/h/d],a|a a,b|b b,

### a tilde after an assignment's first `=` only

```sh
(do (sh-eval "( HOME=/h; for i in 1; do V=a=~/x; W=b:~/y; X=~/z=~; echo \"$V $W $X\"; done; f() { V=c=~; echo \"$V\"; }; f ) | tr '\\n' ','; echo") ())
```
---
    a=~/x b:/h/y /h/z=~,c=~,

### a lone parameter as an argument, quoted and bare

```sh
(do (sh-eval "( for i in 1; do e=; s='a  b'; n=5; g='/no/such*'; printf '<%s>' $e \"$e\" $n \"$n\" ${n} \"${n}\" $s \"$s\" $g; IFS=:; c=x:y; printf '<%s>' $c \"$c\"; unset IFS; done; set -u; f() { printf '<%s>' \"$n\"; echo $nope; }; f ) 2>&1 | tr '\\n' ','; echo") ())
```
---
    <><5><5><5><5><a><b><a  b></no/such*><x><y><x:y><5>ash: nope: parameter not set,

### a lone arithmetic expansion as an argument and as a value

```sh
(do (sh-eval "( for k in 1; do i=7; printf '<%s>' $((i+1)) \"$((i-10))\" $((i*2)); n=0; IFS=1; printf '<%s>' $((n+=101)); echo \" n=$n\"; unset IFS; x=$((i*3)); y=$((x/2)); echo \"$x $y\"; done; f() { echo before; z=$((1+)); echo after; }; f; echo \"st=$?\" ) 2>&1 | tr '\\n' ','; echo") ())
```
---
    <8><-3><14><><0> n=101,21 10,before,ash: arithmetic: syntax error in 1+,

### the status of an assignment, and a read-only name

```sh
(do (sh-eval "( for i in 1; do x=$(false); echo st=$?; x=$(echo s); echo \"$x st=$?\"; y=lit; echo st=$?; done; readonly r=1; for i in 1; do r=2; echo no; done; echo after ) 2>/dev/null | tr '\\n' ','; echo") ())
```
---
    st=1,s st=0,st=0,

### an unset parameter under set -u

```sh
(do (sh-eval "( set -u; for i in 1; do x=$nope; echo no; done; echo after ) 2>/dev/null | tr '\\n' ','; echo") ())
```
---
    

### a loop's commands are not walked going round

The walk that collects a simple command's words is made as often going round
three times as going round once.

```sh
(let ((saved %sh-collect-words)
      (walks 0))
  (def count
    (fn (_ text)
      (set! walks 0)
      (set! %sh-collect-words
        (fn (_ cur ts wds redirs assign?)
          (set! walks (+ walks 1))
          (saved cur ts wds redirs assign?)))
      (guard (e (do (set! %sh-collect-words saved) (error e))) (sh-eval text))
      (set! %sh-collect-words saved)
      walks))
  (= (count "for g9_i in 1; do : a \"$g9_i\" >/dev/null; g9_x=$g9_i; g9_y=\"a $g9_x\"; done")
     (count "for g9_i in 1 2 3; do : a \"$g9_i\" >/dev/null; g9_x=$g9_i; g9_y=\"a $g9_x\"; done")))
```
---
    #t
