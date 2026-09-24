## sh-eval expanding a plain word

Most of a command's words are plain: no `$`, no quotes, no backslash, often
no wildcard.  Such a word is its own single field, and a field that holds no
live wildcard passes pathname expansion as it stands, with nothing appended
to it and no directory read.  A word with a wildcard still reaches the
directory, `set -f` still stops it there, and a pattern that matches nothing
stands with its escapes removed.

Expectations match `/bin/sh` and `dash`.  The first three cases are pins that
hold on main too.  The cost is compared rather than counted, as spec 36
compares its tests.

### plain, quoted and wildcard words

```sh
(do (sh-eval "( d=$(mktemp -d); cd \"$d\"; : > a.c; : > b.c; echo -lt [ 20 ] \"q\" 'r' x\\ y; echo *.c [ab].c; echo *.z \\*.c; set -f; echo *.c; set +f; cd /; rm -rf \"$d\" ) | tr '\\n' ','; echo") ())
```
---
    -lt [ 20 ] q r x y,a.c b.c a.c b.c,*.z *.c,*.c,

### the fields an expansion splits into

```sh
(do (sh-eval "( v='p q'; printf '[%s]' $v \"$v\" '' x\"$v\"y; echo; set -- $v; echo $# ) | tr '\\n' ','; echo") ())
```
---
    [p][q][p q][][xp qy],2,

### a case subject and pattern, a redirection target, a pattern operand

```sh
(do (sh-eval "( x=abc; case $x in a*) echo case;; esac; case \"*\" in \\*) echo star;; esac; f=$(mktemp); echo red > \"$f\"; cat \"$f\"; rm -f \"$f\"; echo ${x#a} ${x%c} ) | tr '\\n' ','; echo") ())
```
---
    case,star,red,bc ab,

### expanding `-lt` ten times costs less than twenty comparisons

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (tok (first (%sh-mark-keywords (sh-tokenize "-lt")))))
  (< (cost (fn (_) ((fn (self i) (if (fx<? i 10) (do (%sh-expand-tok tok ()) (self (fx+ i 1))) ())) 0)))
     (cost (fn (_) ((fn (self i) (if (fx<? i 20) (do (>= i 3) (self (fx+ i 1))) ())) 0)))))
```
---
    #t
