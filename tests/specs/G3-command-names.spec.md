## sh-eval a literal command name is looked up once

What a literal command name is -- the builtin it runs, and whether it is a
declaration utility -- depends on its text alone, so it is asked the first time
the name's token names a command and kept on the token.  A name from an
expansion is looked up each time, and a function is always looked up first, so
one defined over a builtin takes over at once.  A `[` that no class closes is
no pattern, so it is a literal word, and `[` names its command as `test` does.

The first two cases are pins that hold on main too; their expectations match
`dash` and `/bin/sh`.  The last two fail on main.

### a function defined over a builtin, and a name from an expansion

```sh
(do (sh-eval "( for i in 1 2 3; do echo \"a$i\"; if [ $i = 2 ]; then echo() { printf 'fn:%s\\n' \"$*\"; }; fi; done; unset -f echo; c=echo; $c back ) | tr '\\n' ','; echo") ())
```
---
    a1,a2,fn:a3,back,

### a `[` in a word, with a class after it and without

```sh
(do (sh-eval "( cd /tmp && mkdir -p g3.$$ && cd g3.$$ && touch a b; echo [ ] [c a[ [ab] [; [ a = a ] && echo same; cd .. && rm -r g3.$$ ) | tr '\\n' ','; echo") ())
```
---
    [ ] [c a[ a b [,same,

### a `[` no class closes is a literal word

```sh
(write (first (%sh-mark-command (sh-tokenize "[ a ] [ab] x["))))
```
---
    ((tok-lit "[") (tok-lit "a") (tok-lit "]") (tok-word "[ab]") (tok-lit "x["))

### a loop's builtin is looked up once however often it goes round

The builtins are looked up as often going round three times as going round once.

```sh
(let ((saved %sh-table-get)
      (looks 0)
      (run (fn (_ text)
             (let ((ts (first (%sh-mark-command (sh-tokenize text)))))
               (fn (_) (%eval-list (%mk-cursor ts)))))))
  (def count
    (fn (_ text)
      (def thunk (run text))
      (set! looks 0)
      (set! %sh-table-get
        (fn (_ key table)
          (match ((same? table %sh-builtin-table) (set! looks (+ looks 1))) (#t ()))
          (saved key table)))
      (guard (e (do (set! %sh-table-get saved) (error e))) (thunk))
      (set! %sh-table-get saved)
      looks))
  (= (count "for g3_i in 1; do : ; [ 1 = 1 ]; done")
     (count "for g3_i in 1 2 3; do : ; [ 1 = 1 ]; done")))
```
---
    #t
