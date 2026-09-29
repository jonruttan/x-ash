## sh-eval subshells and redirected compounds read into nodes

A subshell in a loop or a function, and a compound command there with
redirections after it, are read with the loop or the function, as its other
compound commands are: the subshell's body to its `)`, and the construct to
where the skip over it ends, the redirections after it collected each time it
runs.  One whose walks read otherwise is walked over its tokens as before.

The first two cases are pins that hold on main too; their expectations match
`dash` and `/bin/sh`.  The last fails on main.

### subshells in loops and functions

```sh
(do (sh-eval "( x=top; for i in 1 2; do ( x=in$i; echo $x ); echo $x; done; for i in 1 2 3; do ( exit $i ); echo st=$?; done; for i in 1 2 3; do ( break ); echo b$i; done; for i in 1 2; do ( trap \"echo trap$i\" EXIT; echo body$i ); done; f() { ( return 3 ); echo st=$?; }; f ) | tr '\\n' ','; echo") ())
```
---
    in1,top,in2,top,st=1,st=2,st=3,b1,b2,b3,body1,trap1,body2,trap2,st=3,

### redirected compounds in loops and functions

A redirection's target is expanded each time round, and a construct whose
redirection fails does not run.

```sh
(do (sh-eval "( for i in 1 2; do { echo t$i; } > /tmp/g7.$i.$$; done; cat /tmp/g7.1.$$ /tmp/g7.2.$$; rm -f /tmp/g7.1.$$ /tmp/g7.2.$$; for i in 1 2; do { echo no; } < /tmp/g7-none-$$; [ $? -ne 0 ] && echo refused; done 2>/dev/null; for i in 1 2; do if [ $i = 1 ]; then echo one; else echo two; fi > /tmp/g7.$$; cat /tmp/g7.$$; done; rm -f /tmp/g7.$$; for i in 1 2 3; do { [ $i = 2 ] && break; echo $i; } > /dev/null; echo after$i; done; f() { echo body$1; } > /tmp/g7.$$; f 1; f 2; cat /tmp/g7.$$; rm -f /tmp/g7.$$ ) | tr '\\n' ','; echo") ())
```
---
    t1,t2,refused,refused,one,two,after1,body2,

### a loop's subshells and redirected compounds are read once

The skip over a construct, made to find the redirections after it, is made as
often going round three times as going round once.

```sh
(let ((saved %sh-skip-compound-walk)
      (walks 0))
  (def count
    (fn (_ text)
      (set! walks 0)
      (set! %sh-skip-compound-walk
        (fn (_ ts depth paren?)
          (set! walks (+ walks 1))
          (saved ts depth paren?)))
      (guard (e (do (set! %sh-skip-compound-walk saved) (error e))) (sh-eval text))
      (set! %sh-skip-compound-walk saved)
      walks))
  (= (count "for g7_i in 1; do ( : a ); { : b; } > /dev/null; done")
     (count "for g7_i in 1 2 3; do ( : a ); { : b; } > /dev/null; done")))
```
---
    #t
