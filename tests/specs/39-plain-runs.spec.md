## sh-eval where a plain run ends

A plain run is the ordinary text the expansion walk takes in one step.  It ends
at the first character the walk has an arm for: a `"`, a backslash, a backtick
or a `$` outside single quotes; a `'` where it opens a region, which is outside
quotes but not inside double ones, where it is text; only the closing quote
inside single quotes; and a `~` only where one could expand.  Along the way the run notes whether it
holds a metacharacter, `*`, `?`, `[` or `\`, which is what makes its field a
pattern.

Each character is decided by one match, and once a run has found a
metacharacter it stops asking.  The cost is compared rather than counted: past
a wildcard, a character costs less than one platform comparison.

The characters are printable ASCII, shown by code.

### what ends a bare run

```sh
(let ((stops (fn (self c mode tilde? acc)
               (if (= c 127)
                 (reverse acc)
                 (self (+ c 1) mode tilde?
                   (if (= 0 (%sh-run-end (%sh-plain-run (list->string (list (integer->char c))) 0 1 mode () tilde?)))
                     (pair c acc)
                     acc))))))
  (stops 32 %sh-mode-bare () ()))
```
---
    (34 36 39 92 96)

### a tilde ends one where it could expand

```sh
(let ((stops (fn (self c mode tilde? acc)
               (if (= c 127)
                 (reverse acc)
                 (self (+ c 1) mode tilde?
                   (if (= 0 (%sh-run-end (%sh-plain-run (list->string (list (integer->char c))) 0 1 mode () tilde?)))
                     (pair c acc)
                     acc))))))
  (stops 32 %sh-mode-bare #t ()))
```
---
    (34 36 39 92 96 126)

### inside double quotes a quote mark is not one of them

A `'` is ordinary text there, so the run reads straight past it: `"it's"` is
one word.

```sh
(let ((stops (fn (self c mode tilde? acc)
               (if (= c 127)
                 (reverse acc)
                 (self (+ c 1) mode tilde?
                   (if (= 0 (%sh-run-end (%sh-plain-run (list->string (list (integer->char c))) 0 1 mode () tilde?)))
                     (pair c acc)
                     acc))))))
  (stops 32 %sh-mode-dq () ()))
```
---
    (34 36 92 96)

### inside single quotes only the closing quote does

```sh
(let ((stops (fn (self c mode tilde? acc)
               (if (= c 127)
                 (reverse acc)
                 (self (+ c 1) mode tilde?
                   (if (= 0 (%sh-run-end (%sh-plain-run (list->string (list (integer->char c))) 0 1 mode () tilde?)))
                     (pair c acc)
                     acc))))))
  (stops 32 %sh-mode-sq () ()))
```
---
    (39)

### the metacharacters a run notes

Read in single quotes, where a backslash does not end the run.

```sh
(let ((metas (fn (self c acc)
               (if (= c 127)
                 (reverse acc)
                 (self (+ c 1)
                   (if (%sh-run-meta? (%sh-plain-run (list->string (list (integer->char c))) 0 1 %sh-mode-sq () ()))
                     (pair c acc)
                     acc))))))
  (metas 32 ()))
```
---
    (42 63 91 92)

### a run notes a metacharacter anywhere in it

```sh
(list (%sh-run-meta? (%sh-plain-run "abc*def" 0 7 %sh-mode-bare () ()))
      (%sh-run-end (%sh-plain-run "abc*def" 0 7 %sh-mode-bare () ()))
      (%sh-run-end (%sh-plain-run "ab$cd" 0 5 %sh-mode-bare () ())))
```
---
    (#t 7 2)

### past a wildcard, a character costs less than one comparison

Each cost is taken net of what measuring an empty call costs, since ten
comparisons would otherwise count that overhead ten times.

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (let ((base (cost (fn (_) ()))))
    (< (- (cost (fn (_) (%sh-plain-run "*bcdefghij" 0 10 %sh-mode-bare () ()))) base)
       (* 10 (- (cost (fn (_) (>= 5 1))) base)))))
```
---
    #t
