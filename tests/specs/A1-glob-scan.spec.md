## sh-eval scanning a value for glob characters

An expansion's value is scanned before it goes into a word: for a wildcard,
which makes the field a pattern, and for a backslash, which has to go in
escaped.  The scan runs over every character of every value, so it steps on
the integer doors rather than the platform's `>=` and `+`, and asks each
character with a `match`.

The classes are checked over every byte.  The cost is compared rather than
counted, as spec 36 compares its tests: a scan costs less than one platform
comparison per character.

### every glob character

```sh
(let ((class (fn (self p i acc)
               (if (= i 256)
                 (list->string (reverse acc))
                 (self p (+ i 1)
                   (if (p (list->string (list (integer->char i))))
                     (pair (integer->char i) acc)
                     acc))))))
  (class %sh-has-glob-meta? 0 ()))
```
---
    "*?[\\"

### the wildcards among them

```sh
(let ((class (fn (self p i acc)
               (if (= i 256)
                 (list->string (reverse acc))
                 (self p (+ i 1)
                   (if (p (list->string (list (integer->char i))))
                     (pair (integer->char i) acc)
                     acc))))))
  (class %sh-has-active-glob? 0 ()))
```
---
    "*?["

### and the one that is not a wildcard

```sh
(let ((class (fn (self p i acc)
               (if (= i 256)
                 (list->string (reverse acc))
                 (self p (+ i 1)
                   (if (p (list->string (list (integer->char i))))
                     (pair (integer->char i) acc)
                     acc))))))
  (class %sh-has-glob-inert? 0 ()))
```
---
    "\\"

### found anywhere in a value

```sh
(list (%sh-has-active-glob? "a*") (%sh-has-active-glob? "*a")
      (%sh-has-glob-inert? "a\\b") (%sh-has-glob-meta? "/usr/local/bin")
      (%sh-has-glob-meta? ""))
```
---
    (#t #t #t () ())

### a scan costs less than one comparison per character

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (text "/usr/local/bin"))
  (< (cost (fn (_) (%sh-has-glob-meta? text)))
     (cost (fn (_) ((fn (self i)
                      (if (fx<? i (string-length text))
                        (do (>= (string-ref text i) #\*) (self (fx+ i 1)))
                        ()))
                    0)))))
```
---
    #t
