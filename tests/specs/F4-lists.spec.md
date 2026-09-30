## sh-eval lists and pipelines from the token list

A list is read from the token list: past a separator and the newlines after
it, a stop word ends the list, and the cursor is written once where the next
command starts.  A simple command that is a pipeline of its own runs on the
list's cursor where it stands, with no stage collected, and what is left
before its stage's end is refused.  `&&` and `||` are told by their two
characters, and an operand that does not run is skipped on the token list.

The first four cases are pins that hold on main too, and match `dash` and
`/bin/sh`.  The fifth matches them too: a complete command is read whole
before any of it runs, so a stage refused refuses the command, where main ran
the command before refusing what was left of its stage.  The last counts the
cursor's writes.

### separators, blank lines and a trailing `;`

```sh
(do (sh-eval "( echo a; echo b;echo c ; echo d;\n\necho e ) | tr '\\n' ','; echo") ())
```
---
    a,b,c,d,e,

### && and || across lines, and the operands they skip

```sh
(do (sh-eval "( false && echo a | tr a b; true || (echo no); false && { echo no; } || echo yes; true &&\necho nl; true || if :; then echo no; fi; echo end ) | tr '\\n' ','; echo") ())
```
---
    yes,nl,end,

### `!`, pipelines and their statuses

```sh
(do (sh-eval "( ! true; echo $?; ! echo a | grep b; echo $?; echo abc | tr b x | tr c y ) | tr '\\n' ','; echo") ())
```
---
    1,0,axy,

### set -e spares a condition, an operand and a negation

```sh
(do (sh-eval "( set -e; false || true; false && true; ! true; if false; then :; fi; echo ok ) | tr '\\n' ','; echo") ())
```
---
    ok,

### what is left of a stage is refused

```sh
(do (sh-eval "{ ( eval 'echo a (' ) 2>&1; echo $?; } | tr '\\n' ','; echo") ())
```
---
    ash: parse error: unexpected (,2,

### a command, a separator and a connective write the cursor once each

```sh
(let ((saved set-first!)
      (writes 0)
      (run (fn (_ text)
             (let ((ts (first (%sh-mark-command (sh-tokenize text)))))
               (fn (_) (%eval-list (%mk-cursor ts)))))))
  (def count
    (fn (_ text)
      (def thunk (run text))
      (thunk)
      (set! writes 0)
      (set! set-first! (fn (_ p v) (set! writes (+ writes 1)) (saved p v)))
      (guard (e (do (set! set-first! saved) (error e))) (thunk))
      (set! set-first! saved)
      writes))
  (list (count ":") (count ":; :") (count ": && :") (count "false || :")))
```
---
    (1 3 3 3)
