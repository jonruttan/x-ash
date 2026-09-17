## sh-eval a token that cannot be read is an error

Evaluating as it reads, the parser stops in front of a token it cannot take --
a word after `fi`, a `)` that closes nothing -- and everything after that
token would never run.  It is a syntax error, named with the token.

`/bin/sh` and `dash` refuse these scripts before running any of them; ash runs
as it reads, so the commands before the token have run by the time it is
reported.  A function body is read when the function is called, so a token
left after the body is reported there.

### a word after a brace group

```sh
(do (sh-eval "{ echo a; } junk; echo b") ())
```
---
    Error: parse error: unexpected junk

### a word after fi

```sh
(do (sh-eval "if true; then echo a; fi junk; echo b") ())
```
---
    Error: parse error: unexpected junk

### a word after done

```sh
(do (sh-eval "for i in 1; do echo $i; done junk; echo b") ())
```
---
    Error: parse error: unexpected junk

### a word after esac

```sh
(do (sh-eval "case x in x) echo c;; esac junk; echo b") ())
```
---
    Error: parse error: unexpected junk

### a word after a subshell

```sh
(do (sh-eval "( echo a ) junk; echo b") ())
```
---
    Error: parse error: unexpected junk

### a paren that closes nothing

```sh
(do (sh-eval "echo a; ); echo b") ())
```
---
    Error: parse error: unexpected )

### a clause terminator outside a case

```sh
(do (sh-eval "echo a; ;; echo b") ())
```
---
    Error: parse error: unexpected ;;

### a word after a function body, at the call

```sh
(do (sh-eval "f() { echo f; } junk; f") ())
```
---
    Error: parse error: unexpected junk

### a pipeline stage reads to its own end

```sh
(do (sh-eval "echo a | { tr a A; } junk") ())
```
---
    Error: parse error: unexpected junk

### an ordinary command is untouched

```sh
(do (sh-eval "{ echo a; }; if true; then echo b; fi; for i in 1; do echo c; done") ())
```
---
    c

### and so is a compound with a redirection

```sh
(do (sh-eval "t=$(mktemp); { echo a; } > \"$t\"; o=$(cat \"$t\"); rm -f \"$t\"; echo \"got=$o\"") ())
```
---
    got=a
