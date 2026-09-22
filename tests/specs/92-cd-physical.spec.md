## sh-eval cd -L and -P, pwd -L and -P

`cd` and `pwd` work on the logical directory, the route the shell took with
any symlink on it left as written.  `cd -P` goes where the kernel resolves
the operand, `..` after a symlink included, and PWD becomes the resolved
path; `pwd -P` prints the resolved path.  `-L` is the default, letters may
run together, the last of `-L` and `-P` decides, and `--` ends them.

Expectations match `/bin/sh` and `dash`.  A temporary directory can itself be
under a symlink (macOS's /var), so the cases look at the path's last part.

### cd -P . resolves the link the shell came through

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir \"$d/real\"; ln -s real \"$d/link\"; cd \"$d/link\"; cd -P .; case $(pwd) in */real) echo physical;; *) echo \"no: $(pwd)\";; esac; cd /; rm -rf \"$d\" )") ())
```
---
    physical

### without it the link stays

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir \"$d/real\"; ln -s real \"$d/link\"; cd \"$d/link\"; case $(pwd) in */link) echo logical;; esac; cd /; rm -rf \"$d\" )") ())
```
---
    logical

### cd -P resolves its operand

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir \"$d/real\"; ln -s real \"$d/link\"; cd -P \"$d/link\"; case $(pwd) in */real) echo physical-operand;; esac; cd /; rm -rf \"$d\" )") ())
```
---
    physical-operand

### cd -P .. goes to the real parent

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir -p \"$d/a/b\"; ln -s a/b \"$d/l\"; cd \"$d/l\"; cd -P ..; case $(pwd) in */a) echo phys-parent;; *) echo \"no: $(pwd)\";; esac; cd /; rm -rf \"$d\" )") ())
```
---
    phys-parent

### cd .. comes back past the link

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir -p \"$d/a/b\"; ln -s a/b \"$d/l\"; cd \"$d/l\"; cd ..; [ \"$(pwd)\" = \"$d\" ] && echo logical-parent; cd /; rm -rf \"$d\" )") ())
```
---
    logical-parent

### the last of -L and -P decides

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir \"$d/real\"; ln -s real \"$d/link\"; cd \"$d/link\"; cd -L -P .; case $(pwd) in */real) echo last-wins-P;; esac; cd /; rm -rf \"$d\" )") ())
```
---
    last-wins-P

### either way round

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir \"$d/real\"; ln -s real \"$d/link\"; cd \"$d/link\"; cd -P -L .; case $(pwd) in */link) echo last-wins-L;; esac; cd /; rm -rf \"$d\" )") ())
```
---
    last-wins-L

### letters run together

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir \"$d/real\"; ln -s real \"$d/link\"; cd \"$d/link\"; cd -LP .; case $(pwd) in */real) echo cluster-P;; esac; cd /; rm -rf \"$d\" )") ())
```
---
    cluster-P

### -- ends them

```sh
(do (sh-eval "( d=$(mktemp -d); cd -- \"$d\" && [ \"$(pwd)\" = \"$d\" ] && echo dashdash; cd /; rm -rf \"$d\" )") ())
```
---
    dashdash

### PWD is the resolved path after cd -P

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir \"$d/real\"; ln -s real \"$d/link\"; cd -P \"$d/link\"; [ \"$PWD\" = \"$(pwd -P)\" ] && echo pwd-var-physical; cd /; rm -rf \"$d\" )") ())
```
---
    pwd-var-physical

### pwd -P

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir \"$d/real\"; ln -s real \"$d/link\"; cd \"$d/link\"; case $(pwd -P) in */real) echo pwd-P;; esac; cd /; rm -rf \"$d\" )") ())
```
---
    pwd-P

### pwd -L

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir \"$d/real\"; ln -s real \"$d/link\"; cd \"$d/link\"; case $(pwd -L) in */link) echo pwd-L;; esac; cd /; rm -rf \"$d\" )") ())
```
---
    pwd-L

### cd - goes back to the logical directory it left

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir \"$d/real\"; ln -s real \"$d/link\"; cd \"$d/link\"; cd -P .; cd - >/dev/null; case $(pwd) in */link) echo back-logical;; esac; cd /; rm -rf \"$d\" )") ())
```
---
    back-logical
