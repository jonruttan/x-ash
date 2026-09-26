## sh-eval the text of the shell's numbers

The shell writes numbers as text for `$?`, `$$`, `$!`, `$#`, `${#X}`, an
arithmetic expansion's value, `OPTIND`, and a here-document's index.  A
fixnum is written by `%number->str`, the platform's own number printer, the
one its printer uses for every integer; any other number -- a bignum out of
arithmetic -- goes through `convert`, as every number did.

Expectations match `/bin/sh` and `dash`.  The cost is compared rather than
counted, as spec 36 compares its tests.

### a status

```sh
(do (sh-eval "( false; a=$?; ( exit 200 ); b=$?; echo \"[$a][$b]\" )") ())
```
---
    [1][200]

### a count and a length

```sh
(do (sh-eval "( set -- a b c; x=hello; echo \"[$#][${#x}]\" )") ())
```
---
    [3][5]

### arithmetic, negative too

```sh
(do (sh-eval "( echo \"[$((1+2))] [$((-7))] [$((2*3*7))] [$((100/3))]\" )") ())
```
---
    [3] [-7] [42] [33]

### a bignum still has its digits

```sh
(%ash-number->str (+ 12345678901234567890 1))
```
---
    "12345678901234567891"

### expanding `$?` costs less than converting the status

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) (%sh-var-value "?"))) (cost (fn (_) (convert 0 %ash-string-type)))))
```
---
    #t
