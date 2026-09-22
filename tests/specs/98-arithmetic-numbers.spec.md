## sh-eval an arithmetic number's value

An arithmetic constant is read by one digit loop whatever its base: decimal,
octal after a leading `0`, hexadecimal after `0x`.  Text that is not digits
alone -- a variable holding a word -- reads as 0.  The digit loop costs less
than the platform's conversion, which is kept for that last case alone.

The cost is compared rather than counted, as spec 36 compares its tests.

### each base

```sh
(write (list (%sh-ar-num "12") (%sh-ar-num "010") (%sh-ar-num "0x1F") (%sh-ar-num "0")))
```
---
    (12 8 31 0)

### a constant past the machine word

```sh
(write (%sh-ar-num "12345678901234567890"))
```
---
    12345678901234567890

### text that is no number

```sh
(write (list (%sh-ar-num "abc") (%sh-ar-num "")))
```
---
    (0 0)

### reading a constant costs less than converting it

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) (%sh-ar-num "12"))) (cost (fn (_) (convert "12" %int)))))
```
---
    #t
