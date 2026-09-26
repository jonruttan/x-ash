## sh-eval character tests

A scan asks one of these of every character it reads: is it a digit, a
hexadecimal digit, a character that can start a name, or one that can
continue a name.  Each is decided with the integer primitive, which compares
a character as its code point and allocates nothing, rather than with the
platform's `<`, `<=` and `>=`, which are wrappers costing hundreds of heap
objects a comparison.

The classes are checked over every byte.  The costs are compared rather than
counted: a character test must cost less than one platform comparison, and
telling whether a name is all digits less than one conversion.

### the digits

```sh
(let ((class (fn (self p i acc)
               (if (= i 256)
                 (list->string (reverse acc))
                 (self p (+ i 1) (if (p (integer->char i)) (pair (integer->char i) acc) acc))))))
  (class %sh-digit? 0 ()))
```
---
    "0123456789"

### the hexadecimal digits

```sh
(let ((class (fn (self p i acc)
               (if (= i 256)
                 (list->string (reverse acc))
                 (self p (+ i 1) (if (p (integer->char i)) (pair (integer->char i) acc) acc))))))
  (class %sh-hex-digit? 0 ()))
```
---
    "0123456789ABCDEFabcdef"

### what can start a name

```sh
(let ((class (fn (self p i acc)
               (if (= i 256)
                 (list->string (reverse acc))
                 (self p (+ i 1) (if (p (integer->char i)) (pair (integer->char i) acc) acc))))))
  (class %sh-name-start? 0 ()))
```
---
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"

### what can continue one

```sh
(let ((class (fn (self p i acc)
               (if (= i 256)
                 (list->string (reverse acc))
                 (self p (+ i 1) (if (p (integer->char i)) (pair (integer->char i) acc) acc))))))
  (class %sh-name-char? 0 ()))
```
---
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"

### a code handed over as an integer is classed as its character

The reader passes its analyse hooks an integer rather than a character.

```sh
(let ((same (fn (self p i)
              (match
                ((= i 256) #t)
                ((eq? (if (p i) #t ()) (if (p (integer->char i)) #t ())) (self p (+ i 1)))
                (#t i)))))
  (list (same %sh-digit? 0) (same %sh-hex-digit? 0)
        (same %sh-name-start? 0) (same %sh-name-char? 0)))
```
---
    (#t #t #t #t)

### a digit test costs less than one comparison

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) (%sh-digit? #\5))) (cost (fn (_) (>= #\5 #\0)))))
```
---
    #t

### so does a name test

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) (%sh-name-start? #\q))) (cost (fn (_) (>= #\q #\a)))))
```
---
    #t

### telling a name is all digits converts nothing

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) (%all-digits? "12"))) (cost (fn (_) (convert #\0 %ash-int-type)))))
```
---
    #t
