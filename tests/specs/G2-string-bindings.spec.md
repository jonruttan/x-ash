## sh-eval the string doors are the platform's own

`string=?` and `string?` are bound to the platform's `str=?` and `str?`, as the
byte doors beside them are bound to their primitives: a function that only
passes its arguments on is a call more on every comparison, and the shell
compares names and words throughout -- a command's name against the builtins,
a variable's name against the table, a `case` subject against its patterns.

The first case pins the answers, and holds on main too.  The second fails on
main.

### the answers

```sh
(list (string=? "ab" "ab") (string=? "ab" "abc") (string=? "" "") (string=? "a" "b")
      (string? "a") (string? 1) (string? ()))
```
---
    (#t #f #t #f #t #f #f)

### the doors are the platform's functions

```sh
(list (same? string=? str=?) (same? string? str?))
```
---
    (#t #t)
