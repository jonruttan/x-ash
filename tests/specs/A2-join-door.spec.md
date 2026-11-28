## sh-eval joining a word's pieces

A field is built as a list of pieces and joined when it closes.  The join is
Str8's own, resolved once through `method-of` as the Sys methods are, and a
field of one piece -- the most common -- is that piece, with no call at all.
What a join answers is what `Str8 join` answers.

### what a join answers

```sh
(list (ash-join "" ()) (ash-join "" (list "a")) (ash-join "" (list "a" "b" "c"))
      (ash-join "/" (list "usr" "local" "bin")))
```
---
    ("" "a" "abc" "usr/local/bin")

### the door is Str8's join

```sh
(same? %str8-join (method-of Str8 (lit join)))
```
---
    #t

### a field's text, in the order its pieces went in

```sh
(%sh-acc-cur (%sh-acc-add (%sh-acc-add (%sh-acc-add %sh-acc-empty "a" ()) "b" ()) "c" ()))
```
---
    "abc"

### closing a field of one piece answers the piece itself

No new string is made: the field's text is the piece that went in.

```sh
(let ((piece (Str8 join "" (list "p" "q"))))
  (same? piece (%sh-acc-cur (%sh-acc-add %sh-acc-empty piece ()))))
```
---
    #t
