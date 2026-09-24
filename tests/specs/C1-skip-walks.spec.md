## sh-eval skipping a construct

A construct is read past without being run in two places: before a compound
command runs, to find the redirections written after it, and where a branch,
a loop body or a case clause is not taken.  Both walks count nesting over the
token list and set the cursor once, where they stop.  A nested construct
inside what is skipped is balanced, and a subshell counts its parens but not a
case pattern's.

Expectations match `/bin/sh` and `dash`.  The first two cases are pins that
hold on main too.  The cost is compared rather than counted, as spec 36
compares its tests.

### branches, loop bodies and clauses not taken

```sh
(do (sh-eval "( if false; then if true; then echo no; fi; case x in x) echo no;; esac; while false; do :; done; else echo else; fi; for i in 1 2; do if [ $i = 1 ]; then continue; fi; echo $i; done; case b in a) if true; then echo a; fi;; b) echo b;; esac; if true; then echo a; elif true; then echo b; else echo c; fi ) | tr '\\n' ','; echo") ())
```
---
    else,2,b,a,

### redirections after a construct that holds others

```sh
(do (sh-eval "( f=$(mktemp); { if true; then echo in; fi; } > \"$f\"; cat \"$f\"; for i in 1 2; do case $i in 1) echo one;; *) echo other;; esac; done > \"$f\"; cat \"$f\"; rm -f \"$f\"; ( case x in x) echo paren;; esac ) | cat; while false; do if true; then :; fi; done; echo after ) | tr '\\n' ','; echo") ())
```
---
    in,one,other,paren,after,

### skipping `if true; then :; fi` costs less than ten comparisons

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (toks (%sh-mark-keywords (sh-tokenize "if true; then :; fi"))))
  (< (cost (fn (_) (%sh-skip-compound (%mk-cursor toks) 0 ())))
     (cost (fn (_) ((fn (self i) (if (fx<? i 10) (do (>= i 3) (self (fx+ i 1))) ())) 0)))))
```
---
    #t
