## sh-eval a word with nothing to expand

A bare word that is one run of plain characters -- `true`, `-lt`, `*.c` -- has
nothing to expand, and stands as its own single field: the text it arrived
as, marked a pattern when it holds a live wildcard.  Any other word is walked,
and the walk starts past the word's leading plain run rather than reading it
again.

A word opening with `~` is walked however it continues, because whether that
tilde expands depends on where it stands.

A field is shown as its text, whether it is a pattern, and whether it carries
escapes.

### a plain word is its own field

```sh
(write (%sh-expand-str "true" %sh-mode-bare #t ()))
```
---
    (("true" () ()))

### the same text, not a copy of it

```sh
(let ((w "true"))
  (same? (first (first (%sh-expand-str w %sh-mode-bare #t ()))) w))
```
---
    #t

### a plain word holding a wildcard is a pattern

```sh
(write (%sh-expand-str "*.c" %sh-mode-bare #t ()))
```
---
    (("*.c" #t ()))

### a tilde inside a plain run is plain

```sh
(write (%sh-expand-str "a~b" %sh-mode-bare #t ()))
```
---
    (("a~b" () ()))

### a plain prefix joins the expansion after it

```sh
(do (sh-eval "ASH_P=VAL")
    (write (%sh-expand-str "a$ASH_P" %sh-mode-bare #t ())))
```
---
    (("aVAL" () ()))

### and the quoted text after it

```sh
(write (%sh-expand-str "pre'lit'post" %sh-mode-bare #t ()))
```
---
    (("prelitpost" () ()))

### a tilde in first place still expands

```sh
(equal? (%sh-expand-str "~/x" %sh-mode-bare #t ())
        (list (list (string-append (sh-getenv "HOME") "/x") () ())))
```
---
    #t

### so does an assignment's tilde after its plain name

```sh
(equal? (%sh-expand-str "x=~/y" %sh-mode-bare () #t)
        (list (list (string-append "x=" (string-append (sh-getenv "HOME") "/y")) () ())))
```
---
    #t

### a double-quoted word is walked

```sh
(write (%sh-expand-str "a b" %sh-mode-dq () ()))
```
---
    (("a b" () ()))
