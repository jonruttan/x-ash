## sh-eval globbing in the cheapest forms

A directory's names are matched first and only the ones a pattern keeps are
sorted, by a merge sort that walks pairs.  A literal directory with a pattern
after it is joined on without being looked for, as dash's expmeta does: the
reading of the directory it leads to finds out whether it is there.  The
split, the walk and the class arm of the matcher are written in the forms
that allocate least.

The first four cases are pins that hold on main too; their expectations match
`dash`.  The next two count what a glob asks for: the names it compares and
the paths it looks up.  The costs are compared rather than counted.

### names come out in byte order

```sh
(do (sh-eval "( d=$(mktemp -d); cd \"$d\"; touch b a _x 10 9 Z; echo *; cd /; rm -rf \"$d\" )") ())
```
---
    10 9 Z _x a b

### a directory that is not there, or is a file, leaves the pattern standing

```sh
(do (sh-eval "( d=$(mktemp -d); cd \"$d\"; touch f; echo nosuch/* f/* \"$d\"/nosuch/*.c | sed \"s|$d|D|\"; cd /; rm -rf \"$d\" )") ())
```
---
    nosuch/* f/* D/nosuch/*.c

### a literal directory after a pattern, and a literal name at the end

```sh
(do (sh-eval "( d=$(mktemp -d); cd \"$d\"; mkdir -p a/src b/src c; touch a/src/x.c b/src/y.c b/src/z.h a/Makefile c/Makefile; echo */src/*.c */Makefile */nosuch; cd /; rm -rf \"$d\" )") ())
```
---
    a/src/x.c b/src/y.c a/Makefile c/Makefile */nosuch

### classes, ranges and negation

```sh
(do (sh-eval "( d=$(mktemp -d); cd \"$d\"; touch a1 b2 c3 A9 _u; echo [!a]* [a-c][0-9] [[:upper:]]* [[:digit:]]*; cd /; rm -rf \"$d\" )") ())
```
---
    A9 _u b2 c3 a1 b2 c3 A9 [[:digit:]]*

### only a literal name after the last pattern is looked up

Every literal directory of an absolute path leads to the pattern after it, so
none is looked up; `Makefile` follows the last pattern, so it is looked up in
each of the two directories `*` reached.

```sh
(let ((saved sh-path-kind)
      (asked 0))
  (sh-eval "d=$(mktemp -d); mkdir -p \"$d/src\" \"$d/sub/a\" \"$d/sub/b\"; touch \"$d/src/x.c\" \"$d/sub/a/Makefile\"")
  (set! sh-path-kind (fn (_ path) (set! asked (+ asked 1)) (saved path)))
  (sh-eval "set -- $d/src/*.c")
  (def before asked)
  (sh-eval "set -- $d/sub/*/Makefile")
  (def after asked)
  (set! sh-path-kind saved)
  (sh-eval "rm -rf \"$d\"")
  (list before (- after before)))
```
---
    (0 2)

### a pattern that matches nothing compares no names

Forty names are read, none matches, and none is compared; the eleven that
`n1*` keeps are.

```sh
(let ((saved %str8-less)
      (compared 0))
  (sh-eval "d=$(mktemp -d); i=0; while [ $i -lt 40 ]; do : > \"$d/n$i\"; i=$((i+1)); done")
  (def dir (%sh-var-get "d"))
  (set! %str8-less (fn (_ cls a b) (set! compared (+ compared 1)) (saved cls a b)))
  (def none (length (%sh-glob-entries dir "*.nosuch")))
  (def none-compared compared)
  (def some (length (%sh-glob-entries dir "n1*")))
  (set! %str8-less saved)
  (sh-eval "rm -rf \"$d\"")
  (list none none-compared some (< 0 compared)))
```
---
    (0 0 11 #t)

### five names sort for less than twenty comparisons

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (ge5 (fn (_) (do (>= 5 1) (>= 5 1) (>= 5 1) (>= 5 1) (>= 5 1)))))
  (< (cost (fn (_) (sh-sort-strings (list "g5.c" "g3.c" "g1.c" "g4.c" "g2.c"))))
     (cost (fn (_) (do (ge5) (ge5) (ge5) (ge5))))))
```
---
    #t

### a path splits for less than twenty comparisons

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (ge5 (fn (_) (do (>= 5 1) (>= 5 1) (>= 5 1) (>= 5 1) (>= 5 1)))))
  (< (cost (fn (_) (%sh-glob-split "usr/local/share/x/lib/*.x")))
     (cost (fn (_) (do (ge5) (ge5) (ge5) (ge5))))))
```
---
    #t

### a negated class matches for less than twenty comparisons

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (ge5 (fn (_) (do (>= 5 1) (>= 5 1) (>= 5 1) (>= 5 1) (>= 5 1)))))
  (< (cost (fn (_) (%sh-pattern-match? "*[!a-z]" "f01.txt")))
     (cost (fn (_) (do (ge5) (ge5) (ge5) (ge5))))))
```
---
    #t
