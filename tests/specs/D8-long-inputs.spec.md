## sh-eval long inputs

A script is read into one token list, an expansion can give tens of thousands
of fields, and a directory can hold tens of thousands of entries, so the walks
over these lists are loops.  A call per element nested in the previous one's
`pair`, `append` or `string-append` runs out of C stack at about 30,000
elements, and after a list is built that way the next collect dies too, even
once nothing holds the list, as the next prompt would after a long `.` file.

Each case but the last runs in a child, bounded at a budget of objects above
what it inherited, which answers 7 when it has finished.  On main each of
these children dies with SIGSEGV, 139.  The last pins what a pattern ending
in `/` keeps, directories only and in order, and holds on main too;
expectation from `/bin/sh` and `dash`.

### a script of 32,000 lines runs to its end

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (sh-exit 5))
      (alloc-limit! (+ (Heap count) 45000000))
      (sh-eval (string-append (Str8 repeat 32000 "\n") "d8_long=reached"))
      (sh-exit (if (string=? (%sh-var-get "d8_long") "reached") 7 3)))
    (write (sh-wait pid)))
  ())
```
---
    7

### a collect after a script of 20,000 lines

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (sh-exit 5))
      (alloc-limit! (+ (Heap count) 30000000))
      (sh-eval (Str8 repeat 20000 "\n"))
      ((prim-ref (lit heap) (lit collect)))
      (sh-exit 7))
    (write (sh-wait pid)))
  ())
```
---
    7

### 30,000 fields through the pathname walk

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (sh-exit 5))
      (alloc-limit! (+ (Heap count) 30000000))
      (def build (fn (self n x acc) (if (= n 0) acc (self (- n 1) x (pair x acc)))))
      (def n (length (%sh-glob-fields (build 30000 (%sh-field "a" () ()) ()))))
      (sh-exit (if (= n 30000) 7 3)))
    (write (sh-wait pid)))
  ())
```
---
    7

### 30,000 parameters joined for `"$*"`

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (sh-exit 5))
      (alloc-limit! (+ (Heap count) 30000000))
      (def build (fn (self n x acc) (if (= n 0) acc (self (- n 1) x (pair x acc)))))
      (def s (%sh-join-params (build 30000 "a" ())))
      (sh-exit (if (= (string-length s) 59999) 7 3)))
    (write (sh-wait pid)))
  ())
```
---
    7

### 30,000 directory entries kept

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (sh-exit 5))
      (alloc-limit! (+ (Heap count) 30000000))
      (def build (fn (self n x acc) (if (= n 0) acc (self (- n 1) x (pair x acc)))))
      (def n (length (%sh-keep (fn (_ x) #t) (build 30000 "a" ()))))
      (sh-exit (if (= n 30000) 7 3)))
    (write (sh-wait pid)))
  ())
```
---
    7

### 30,000 directory entries joined to their directory

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (sh-exit 5))
      (alloc-limit! (+ (Heap count) 60000000))
      (def build (fn (self n x acc) (if (= n 0) acc (self (- n 1) x (pair x acc)))))
      (def n (length (%sh-map-join "d" (build 30000 "a" ()))))
      (sh-exit (if (= n 30000) 7 3)))
    (write (sh-wait pid)))
  ())
```
---
    7

### a pattern ending in a slash keeps directories only, in order

```sh
(do (sh-eval "( d=$(mktemp -d); cd \"$d\"; mkdir sub other; touch f g; echo */; cd /; rm -rf \"$d\" )") ())
```
---
    other/ sub/
