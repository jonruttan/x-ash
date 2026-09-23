## sh-eval a simple command's words and redirections

A simple command's tokens are read in order: each word is expanded where it
stands, a redirection -- an operator, or a descriptor's number against one --
takes the word after it as its target, and the command ends at the first
token that is neither.  A redirection may come first, last or between words,
and the words around it are the command's all the same.  The leading
`NAME=value` words are assignments, and so is every argument of a
declaration utility.

Expectations match `/bin/sh` and `dash`, and hold on main too.

### redirections before, between and after the words

```sh
(do (sh-eval "( d=$(mktemp -d); cd \"$d\"; echo a > f b; >g echo x; echo c 2>/dev/null d > h; cat f g h | tr '\\n' ','; cd /; rm -rf \"$d\"; echo )") ())
```
---
    a b,x,c d,

### a descriptor's number against its operator

```sh
(do (sh-eval "( { echo e >&2; } 2>&1 | cat )") ())
```
---
    e

### quoted and empty words

```sh
(do (sh-eval "( x=; echo p $x q \"r s\" 't u' )") ())
```
---
    p q r s t u

### prefix assignments, an assignment's value, and a declaration's argument

```sh
(do (sh-eval "( x=1; x=2 y=3 sh -c 'echo $x$y'; a=b=c; echo $a; export z=5; sh -c 'echo $z' ) | tr '\\n' ','; echo") ())
```
---
    23,b=c,5,
