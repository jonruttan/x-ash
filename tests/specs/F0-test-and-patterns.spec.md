## sh-eval test and pattern scans in the cheapest forms

`[` takes its words before the closing `]` in one walk, and `test` tells how
many there are from the list's structure rather than by counting.  A binary
operator that starts with `-`, the numeric ones and the file dates, is sent
to them by that character before any string operator is compared.  Whether a
word is a pattern, and where a bracket expression in it ends, are scanned on
the integer doors: the lone `[` of every test is such a word.

The first four cases are pins that hold on main too; their expectations match
`/bin/sh` and `dash`.  The costs are compared rather than counted.

### integer operands, padded, signed and led by zeros

```sh
(do (sh-eval "( [ 007 -eq 7 ]; printf %s $?; [ \" 7 \" -eq 7 ]; printf %s $?; [ -3 -lt +2 ]; printf %s $?; [ 5 -ge 5 ]; printf %s $?; [ 5 -ne 5 ]; printf %s $?; echo )") ())
```
---
    00001

### an empty test, a lone bracket, and a missing one

```sh
(do (sh-eval "( [ ]; printf %s $?; [ ] ]; printf %s $?; [ x ] 2>/dev/null; printf %s $?; [ a = a 2>/dev/null; printf %s $?; echo )") ())
```
---
    1002

### a bracket nothing closes is an ordinary character

```sh
(do (sh-eval "( d=$(mktemp -d); cd $d; : > ab; echo [ a[ [] [!] \"*[\" [a]b; cd /; rm -rf $d )") ())
```
---
    [ a[ [] [!] *[ ab

### as a case pattern too

```sh
(do (sh-eval "( for w in \"[\" \"a[\" \"[]\" \"[!]\" \"x\" \"[a]\" \"[ab]\" \"[!a]\"; do case b in $w) printf y;; *) printf n;; esac; done; echo )") ())
```
---
    nnnnnnyy

### expanding the `[` of a test costs less than two plain words

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (open (first (sh-tokenize "[")))
      (plain (first (sh-tokenize "-lt"))))
  (< (cost (fn (_) (%sh-expand-tok open ())))
     (cost (fn (_) (do (%sh-expand-tok plain ()) (%sh-expand-tok plain ()))))))
```
---
    #t

### scanning ten plain characters for a pattern costs less than two comparisons

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) (%sh-glob-pattern? "abcdefghij")))
     (cost (fn (_) (do (>= 5 1) (>= 5 1))))))
```
---
    #t
