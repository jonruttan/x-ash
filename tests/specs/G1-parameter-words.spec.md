## sh-eval a word that is one parameter

A word that is one parameter, bare or in double quotes -- `$x` or `"$x"` --
has its fields made from the value alone.  The value is asked once.  When it
holds nothing field splitting or pathname expansion would act on, it is the
word's one field; a bare empty value is no field, a quoted one an empty field.
Any other value goes in as every expansion does, split on IFS and globbed.

The first three cases are pins that hold on main too; their expectations match
`dash` and `/bin/sh`.  The last two compare costs.

### values a split or a glob acts on, and values neither does

```sh
(do (sh-eval "( cd /tmp && mkdir -p g1.$$ && cd g1.$$ && touch f1 f2; x=abc; set -- $x; printf '%s ' \"$#[$1]\"; x='a b'; set -- $x; printf '%s ' \"$#[$1][$2]\"; set -- \"$x\"; printf '%s ' \"$#[$1]\"; x='f*'; printf '%s ' $x \"$x\"; IFS=:; x='a:b'; set -- $x; printf '%s ' \"$#[$2]\"; cd .. && rm -r g1.$$; echo )") ())
```
---
    1[abc] 2[a][b] 1[a b] f1 f2 f* 2[b] 

### empty and unset, bare and quoted

```sh
(do (sh-eval "( x=; set -- $x; printf '%s ' $#; set -- \"$x\"; printf '%s ' \"$#[$1]\"; unset x; set -- $x; printf '%s ' $#; set -- \"$x\"; printf '%s ' \"$#[$1]\"; echo )") ())
```
---
    0 1[] 0 1[] 

### a word that is more than one parameter

```sh
(do (sh-eval "( IFS=:; x='a:'; y=b; set -- $x$y; printf '%s ' \"$#[$1][$2]\"; IFS=' '; x='a b'; set -- ''$x; printf '%s ' \"$#[$1]\"; set -- \"$x\"$x; printf '%s ' \"$#[$1][$2]\"; echo )") ())
```
---
    2[a][b] 2[a] 2[a ba][b] 

### expanding `$i` costs less than three comparisons

The variables are restored afterwards, so `i` is set for this case alone.  The
token is expanded once before it is measured, so it holds its plan.

```sh
(let ((saved %sh-vars)
      (cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (tok (first (sh-tokenize "$i"))))
  (%sh-var-set! "i" "5")
  (%sh-expand-tok tok ())
  (let ((got (< (cost (fn (_) (%sh-expand-tok tok ())))
                (cost (fn (_) (do (>= 5 1) (>= 5 1) (>= 5 1)))))))
    (set! %sh-vars saved)
    got))
```
---
    #t

### expanding `"$x"` costs less than three comparisons

```sh
(let ((saved %sh-vars)
      (cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (tok (first (sh-tokenize "\"$x\""))))
  (%sh-var-set! "x" "abc")
  (%sh-expand-tok tok ())
  (let ((got (< (cost (fn (_) (%sh-expand-tok tok ())))
                (cost (fn (_) (do (>= 5 1) (>= 5 1) (>= 5 1)))))))
    (set! %sh-vars saved)
    got))
```
---
    #t
