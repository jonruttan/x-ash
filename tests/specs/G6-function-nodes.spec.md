## sh-eval function bodies read into nodes

A function's body is read into nodes at the function's first call, and each
call after it runs what was read: the words of the ifs, cases, groups and
loops in it are found once however often it is called.  A body whose walks
read otherwise is walked over its tokens at every call, as before.

The first three cases are pins that hold on main too; their expectations match
`dash` and `/bin/sh`.  The fourth keeps a read body across collects.  The last
fails on main.

### bodies of each kind

```sh
(do (sh-eval "( f() { if [ $1 = a ]; then echo A; elif [ $1 = b ]; then echo B; else { echo C; }; fi; }; f a; f b; f c; g() { case $1 in x|y) echo xy;; *) echo other;; esac; }; g y; g z; h() for i in 1 2; do echo h$i; done; h; s() ( echo sub$1 ); s 1; r() { echo r; } >/dev/null; r; echo st=$? ) | tr '\\n' ','; echo") ())
```
---
    A,B,C,xy,other,h1,h2,sub1,st=0,

### `return`, `local`, recursion and `set -e`

```sh
(do (sh-eval "( n() { [ $1 -le 0 ] && return 3; echo n$1; n $(($1-1)); }; n 2; echo st=$?; v=out; l() { local v=in; echo $v; }; l; echo $v; e() { false; echo reached; }; set -e; e || echo caught; t() { false; }; t; echo dead ) | tr '\\n' ','; echo") ())
```
---
    n2,n1,st=3,in,out,reached,

### a definition in the body, and `unset -f`

```sh
(do (sh-eval "( f() { echo one; f() { echo two; }; }; f; f; unset -f f; f 2>/dev/null || echo gone ) | tr '\\n' ','; echo") ())
```
---
    one,two,gone,

### a read body is kept across collects

A child process collects before every simple command while a function is
called 20 times, its body read at the first call and run at the rest.

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (sh-exit 5))
      (set! %sh-sweeps? #t)
      (set! %sh-sweep-every 1)
      (set! %sh-sweep-left 1)
      (sh-eval "g6_f() { case $1 in *0) g6_s=\"$g6_s,$1\";; esac; if [ $1 -gt 15 ]; then g6_t=\"t$1\"; fi; }; g6_i=0; while [ $g6_i -lt 20 ]; do g6_i=$((g6_i+1)); g6_f $g6_i; done")
      (sh-exit (if (string=? (string-append (%sh-var-get "g6_s") (%sh-var-get "g6_t")) ",10,20t20") 7 3)))
    (write (sh-wait pid)))
  ())
```
---
    7

### a function's body is read once however often it is called

The walk that finds where a command's stage ends is made as often calling the
function three times as calling it once.

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
  (= (count "g6_g() { if true; then : a; fi; case x in x) : b;; esac; { : c; }; }; for g6_i in 1; do g6_g; done")
     (count "g6_g() { if true; then : a; fi; case x in x) : b;; esac; { : c; }; }; for g6_i in 1 2 3; do g6_g; done")))
```
---
    #t
