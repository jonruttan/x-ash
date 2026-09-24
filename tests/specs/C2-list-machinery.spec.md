## sh-eval the steps around every command

Every command in a list passes through the same few steps.  The list looks for
a closing word and for an `&` ahead, the and-or list runs the pipeline, and the
pipeline takes a leading `!` and runs its stages; after it, the separator and
any blank lines are taken.  Each step reads the token at the cursor where it
stands, decides with `match` and binds with `def`, so the steps cost less
than the command they carry.

Expectations match `/bin/sh` and `dash`.  The first four cases are pins that
hold on main too.  The cost is compared rather than counted, as spec 36
compares its tests.

### separators, connectives and negation

```sh
(do (sh-eval "( true && echo a || echo b; false && echo c || echo d; ! false && echo e; ! true || echo f; echo g & wait; echo h; f() { echo i; }; f ) | tr '\\n' ','; echo") ())
```
---
    a,d,e,f,g,h,i,

### a negation inside a negated pipeline

Each pipeline's `!` and status are its own, however deep a pipeline inside it
runs.

```sh
(do (sh-eval "( ! { true; }; echo \"a$?\"; ! { ! true; }; echo \"b$?\"; ! { false; true; } | cat; echo \"c$?\"; { ! false; } && echo d; ! if true; then ! true; fi; echo \"e$?\" ) | tr '\\n' ','; echo") ())
```
---
    a1,b0,c1,d,e0,

### blank lines inside a construct and after it

```sh
(do (sh-eval "( if true\n\nthen\n\necho a\n\nfi\n\n\necho b ) | tr '\\n' ','; echo") ())
```
---
    a,b,

### what `set -e` exempts

```sh
(do (sh-eval "( ( set -e; false || echo or-ran; ! true; echo after-bang; false && echo no; echo after-and; false; echo not-reached ); echo \"st=$?\" ) | tr '\\n' ','; echo") ())
```
---
    or-ran,after-bang,after-and,st=1,

### running `: ; :` costs less than forty comparisons

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (toks (%sh-mark-keywords (sh-tokenize ": ; :"))))
  (< (cost (fn (_) (%eval-list (%mk-cursor toks))))
     (cost (fn (_) ((fn (self i) (if (fx<? i 40) (do (>= i 3) (self (fx+ i 1))) ())) 0)))))
```
---
    #t
