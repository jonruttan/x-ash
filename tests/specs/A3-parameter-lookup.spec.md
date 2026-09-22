## sh-eval looking a parameter up

A `$` is followed by a name far more often than by anything else, so a name
is asked about first, and looked up without the table of specials: a name
begins with a letter or underscore, and no special's does.  A positional
parameter's number is read by the arithmetic reader's digit loop rather than
`convert`, and the `}` that closes `${...}` is found on the integer doors.

Expectations match `/bin/sh` and `dash`.  The costs are compared rather than
counted, as spec 36 compares its tests.

### the characters that name a one-character parameter

```sh
(let ((class (fn (self p i acc)
               (if (= i 256)
                 (list->string (reverse acc))
                 (self p (+ i 1) (if (p (integer->char i)) (pair (integer->char i) acc) acc))))))
  (class %sh-special-param? 0 ()))
```
---
    "!#$*-0123456789?@"

### one digit after a `$`, and more in braces

```sh
(do (sh-eval "( set -- a b c d e f g h i j k; echo \"$# $1 $10 ${10} ${11}\" )") ())
```
---
    11 a a0 j k

### a name ends where its characters do

```sh
(do (sh-eval "( x=hello; echo \"$x-${x}-${#x}-${x}y-[$x_y]\" )") ())
```
---
    hello-hello-5-helloy-[]

### a `$` that starts nothing is itself

```sh
(do (sh-eval "( echo \"[$]\" \"[$ ]\" \"[$%]\" \"[a$]\" )") ())
```
---
    [$] [$ ] [$%] [a$]

### a quoted brace does not close

```sh
(do (sh-eval "( x='a}b'; echo \"${x}\" \"${x:-\"}\"}\" )") ())
```
---
    a}b a}b

### a name is not asked of the specials

A name that begins with a letter reaches the variables even when the table of
specials is given an entry of its own.

```sh
(let ((saved %sh-special-vars))
  (%sh-var-set! "pl" "variable")
  (set! %sh-special-vars (pair (pair "pl" (fn (_) "special")) saved))
  (let ((got (%sh-var-value "pl")))
    (set! %sh-special-vars saved)
    got))
```
---
    "variable"

### a positional parameter costs less than converting its number

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) (%sh-var-value "1"))) (cost (fn (_) (convert "1" %int)))))
```
---
    #t

### finding a brace costs less than one comparison per character

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) (%sh-brace-end "${i}" 2 4 0)))
     (cost (fn (_) (do (>= #\i #\a) (>= #\} #\a))))))
```
---
    #t
