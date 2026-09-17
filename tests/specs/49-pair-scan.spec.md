## sh-eval asks whether a text needs a pass

Before lifting here-documents out of a text, and before joining its continued
lines, the shell asks whether the text holds `<<`, or a backslash before a
newline, at all.  Most text holds neither, and every text is asked, so the scan
builds nothing: a character costs less than one comparison does.

### a pair of characters is found wherever it stands

```sh
(list (%sh-has-pair? "a<<b" 0 4 #\< #\<)
      (%sh-has-pair? "<<" 0 2 #\< #\<)
      (%sh-has-pair? "ab<<" 0 4 #\< #\<))
```
---
    (#t #t #t)

### but only as a pair, in order

```sh
(list (%sh-has-pair? "a<b<" 0 4 #\< #\<)
      (%sh-has-pair? "<" 0 1 #\< #\<)
      (%sh-has-pair? "" 0 0 #\< #\<)
      (%sh-has-pair? "ba" 0 2 #\a #\b))
```
---
    (() () () ())

### the here-document question is the pair `<<`

```sh
(list (%sh-str-has-heredoc-op? "cat <<EOF")
      (%sh-str-has-heredoc-op? "echo $((3<5))")
      (%sh-str-has-heredoc-op? "a <b"))
```
---
    (#t () ())

### a character costs less than one comparison

Taken net of what measuring an empty call costs, since the comparison is
counted once per character.

```sh
(let ((cost (fn (_ thunk) (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (s "for i in 1 2 3; do if [ $i -gt 1 ]; then echo big $i; else echo small; fi; done"))
  (let ((base (cost (fn (_) ()))))
    (< (- (cost (fn (_) (%sh-str-has-heredoc-op? s))) base)
       (* (string-length s) (- (cost (fn (_) (>= 5 1))) base)))))
```
---
    #t
