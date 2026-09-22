## sh-eval where a pipeline's stages end

A pipeline's tokens are cut into stages at a depth-zero `|`, and the pipeline
ends at a newline, a `;`, `;;`, `&`, `&&`, `||`, or a word that closes an
enclosing construct.  A compound's own separators and closing words belong
to it.  A word that no mark made a keyword -- most of any command -- can end
nothing and nests nothing, so it is taken without being asked.

Expectations match `/bin/sh` and `dash`, and hold on main too.  The cost is
compared rather than counted, as spec 36 compares its tests.

### compounds as stages, and the separators after them

```sh
(do (sh-eval "( echo a | tr a b; ( echo p ) | tr p P; for i in 1 2; do echo $i; done | wc -l | tr -d ' '; case x in x) echo y;; esac | cat ) | tr '\\n' ','; echo") ())
```
---
    b,P,2,y,

### and-or lists, groups and quoted separators

```sh
(do (sh-eval "( true && echo and || echo or; if true; then echo t; fi | cat; { echo g; } | cat; echo \"a;b\" | cat; echo x > /dev/null | cat; echo z ) | tr '\\n' ','; echo") ())
```
---
    and,t,g,a;b,z,

### collecting plain words costs less than one comparison each

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (toks (%sh-mark-keywords (sh-tokenize "echo a b c d e"))))
  (< (cost (fn (_) (%collect-stages (%mk-cursor toks) ())))
     (cost (fn (_) ((fn (self i)
                      (if (fx<? i 6) (do (>= i 3) (self (fx+ i 1))) ()))
                    0)))))
```
---
    #t
