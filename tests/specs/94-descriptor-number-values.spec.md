## sh-eval a descriptor number's value

A redirection's descriptor number, the descriptor `>&` or `<&` duplicates,
and a here-document's index are digits, read once where the shell reaches
them by the arithmetic reader's digit loop rather than by the platform's
conversion.  Anything that is not all digits reads as nil, which is what a
duplicate of a word that names no descriptor is refused on.  The suite's
redirection specs are what show the numbers still reach the descriptors.

The cost is compared rather than counted: reading a number must cost less
than one conversion of it.

### digits read as their number

```sh
(write (list (%sh-digits-int "2") (%sh-digits-int "10") (%sh-digits-int "007")))
```
---
    (2 10 7)

### anything else is nil

```sh
(write (list (%sh-digits-int "") (%sh-digits-int "x1") (%sh-digits-int "1x") (%sh-digits-int "-1")))
```
---
    (() () () ())

### reading one costs less than converting it

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_ ) (%sh-digits-int "2"))) (cost (fn (_) (convert "2" %ash-int-type)))))
```
---
    #t
