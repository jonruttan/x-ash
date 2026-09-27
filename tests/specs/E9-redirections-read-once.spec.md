## sh-eval redirections read from the token list

A simple command's redirections are read from its token list as its words
are, and the cursor is written once, where the command ends.  Whether the
operator that ends a command opens a redirection is told by its first
character, since every redirection operator starts with `<` or `>`.  Making a
redirection, parking the descriptors it changes and putting them back are
written in the forms that allocate least.

The first five cases are pins that hold on main too; their expectations match
`/bin/sh` and `dash`.  The cost is compared rather than counted.

### each file operator

```sh
(do (sh-eval "( d=$(mktemp -d); echo a > $d/f; echo b >> $d/f; cat < $d/f; echo c >| $d/f; cat $d/f; echo rw <> $d/f; cat $d/f; rm -rf $d ) | tr '\\n' ','; echo") ())
```
---
    a,b,c,rw,c,

### descriptors: numbered, duplicated and closed

```sh
(do (sh-eval "( d=$(mktemp -d); cd /nonexistent-e9 2> $d/e; test -s $d/e && echo err; exec 3> $d/g; echo three >&3; exec 3>&-; cat $d/g; exec 4< $d/g; read l <&4; echo $l; exec 4<&-; rm -rf $d ) | tr '\\n' ','; echo") ())
```
---
    err,three,three,

### redirections apply in the order they are written

```sh
(do (sh-eval "( x=$(cd /nonexistent-e9 2>&1 >/dev/null); test -n \"$x\" && echo order; y=$(cd /nonexistent-e9 >/dev/null 2>&1); test -z \"$y\" && echo both ) | tr '\\n' ','; echo") ())
```
---
    order,both,

### a redirection before, among and without the command's words

```sh
(do (sh-eval "( d=$(mktemp -d); >$d/f echo a b; cat $d/f; echo c >$d/g d; cat $d/g; x=1 >$d/h; echo $x; test -f $d/h && echo h-made; rm -rf $d ) | tr '\\n' ','; echo") ())
```
---
    a b,c d,1,h-made,

### a construct's and a call's redirections

```sh
(do (sh-eval "( d=$(mktemp -d); { echo g; } >$d/f; f() { echo fn; }; f >>$d/f; for i in 1; do echo $i; done >>$d/f; cat $d/f; rm -rf $d ) | tr '\\n' ','; echo") ())
```
---
    g,fn,1,

### the operator that ends a command is told from a redirection for less than a comparison

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (semi (first (sh-tokenize "; :"))))
  (< (cost (fn (_) (%redir-op? semi))) (cost (fn (_) (>= 5 1)))))
```
---
    #t
