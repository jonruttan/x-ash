## sh-eval compound commands read the role their reserved words were marked with

The marking walk marks each reserved word it finds with what the word does
there: `opens` a construct, `closes` one, `ends` the list in front of it, or
`stays`.  The scans that run each time a list, a stage or a skipped body is
read -- the `&` scan, stage collection, the skip walks, the stop-word test --
answer with one `eq?` on that mark, where they looked the word up in lists of
words.  A stage that ends with its construct's own closing word has no
redirections after it, and runs without reading the construct twice.  The
list, pipeline and call machinery is written in the forms that allocate
least.

The first five cases are pins that hold on main too; their expectations match
`/bin/sh` and `dash`.  The costs are compared rather than counted.

### calls, their arguments and their statuses

```sh
(do (sh-eval "( f() { echo $#:$1; return 3; }; f a b; echo $?; g() { f x; echo g$?; }; g ) | tr '\\n' ','; echo") ())
```
---
    2:a,3,1:x,g3,

### redirections after a construct still apply to it

```sh
(do (sh-eval "( t=$(mktemp); { echo a; } > $t; if true; then echo b; fi >> $t; for i in c; do echo $i; done >> $t; case x in x) echo d;; esac >> $t; while :; do echo e; break; done >> $t; tr '\\n' ',' < $t; rm -f $t; echo )") ())
```
---
    a,b,c,d,e,

### a closing word after a construct ends the stage it is in

```sh
(do (sh-eval "( if true; then { echo x; } fi; { { echo y; } }; f() { { echo z; }; }; f ) | tr '\\n' ','; echo") ())
```
---
    x,y,z,

### negation, and-or lists and background lists around a brace group

```sh
(do (sh-eval "( ! { false; }; echo $?; { false; } || echo or; { true; } && echo and; { echo bg; } & wait ) | tr '\\n' ','; echo") ())
```
---
    0,or,and,bg,

### a call's locals, and a bare return

```sh
(do (sh-eval "( f() { local v=in; echo $v; }; v=out; f; echo $v; h() { return; }; false; h; echo $? ) | tr '\\n' ','; echo") ())
```
---
    in,out,1,

### each reserved word carries its role

```sh
(map %tok-role (%sh-mark-keywords (sh-tokenize "for i in a; do ! :; done")))
```
---
    (opens () stays () () ends stays () () closes)

### a brace group costs less than three commands

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (toks (fn (_ text) (first (%sh-mark-command (sh-tokenize text))))))
  (let ((brace (toks "{ :; }")) (three (toks ": ; : ; :")))
    (< (cost (fn (_) (%eval-list (%mk-cursor brace))))
       (cost (fn (_) (%eval-list (%mk-cursor three)))))))
```
---
    #t

### calling a function costs less than four commands

The function is removed afterwards, so it is defined for this case alone.

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (toks (fn (_ text) (first (%sh-mark-command (sh-tokenize text))))))
  (sh-eval "e8f() { :; }")
  (let ((call (toks "e8f")) (four (toks ": ; : ; : ; :")))
    (let ((got (< (cost (fn (_) (%eval-list (%mk-cursor call))))
                  (cost (fn (_) (%eval-list (%mk-cursor four)))))))
      (sh-eval "unset -f e8f")
      got)))
```
---
    #t

### a reserved word's nesting costs less than one walk of the openers

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (open (first (%sh-mark-keywords (sh-tokenize "{ :; }")))))
  (< (cost (fn (_) (%sh-nest-delta open)))
     (cost (fn (_) (%sh-word-in? "{" %sh-block-openers)))))
```
---
    #t
