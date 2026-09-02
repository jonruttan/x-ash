## sh-eval expansion

### expands an embedded variable

```sh
(do (sh-eval "X=v; echo pre${X}post") ())
```
---
    prevpost

### expands a name that ends at a non-name character

```sh
(do (sh-eval "X=v; echo $X.txt") ())
```
---
    v.txt

### an unset variable expands to nothing

```sh
(do (sh-eval "echo [$NOSUCHVAR_ASH]") ())
```
---
    []

### a trailing dollar is literal

```sh
(do (sh-eval "echo 50$") ())
```
---
    50$

### an unclosed brace is literal

```sh
(do (sh-eval "echo ${X") ())
```
---
    ${X

## sh-eval test operators

### -d is true for a directory

```sh
(sh-eval "test -d /")
```
---
    0

### -d is false for a path that is not a directory

```sh
(sh-eval "test -d /no-such-path-ash-spec")
```
---
    1

### -e is false for a missing path

```sh
(sh-eval "test -e /no-such-path-ash-spec")
```
---
    1

### -f is false for a directory

```sh
(sh-eval "test -f /")
```
---
    1

### numeric greater-than

```sh
(sh-eval "test 5 -gt 3")
```
---
    0

### numeric greater-than, false

```sh
(sh-eval "test 2 -gt 3")
```
---
    1

### numeric equality

```sh
(sh-eval "test 4 -eq 4")
```
---
    0

### numeric less-than-or-equal

```sh
(sh-eval "test 3 -le 3")
```
---
    0

### an unknown binary operator is a usage error

```sh
(sh-eval "test 1 -zz 2")
```
---
    2

## sh-eval builtins

### echo -n suppresses the newline

```sh
(do (sh-eval "echo -n hi") (newline))
```
---
    hi

### unset removes a variable

```sh
(do (sh-eval "X=v; unset X; echo [$X]") ())
```
---
    []

### pwd reports a non-empty path

```sh
(sh-eval "pwd > /dev/null")
```
---
    0

## sh-eval redirection

### a builtin's redirection is applied and then undone

```sh
(do (sh-eval "echo to-file > /dev/null") (sh-eval "echo to-stdout") ())
```
---
    to-stdout

## sh-eval case patterns

### a trailing-star pattern matches

```sh
(do (sh-eval "case abc in a*) echo hit ;; esac") ())
```
---
    hit

### a leading-star pattern matches a suffix

```sh
(do (sh-eval "case foo.txt in *.txt) echo txt ;; esac") ())
```
---
    txt

### ? matches exactly one character

```sh
(do (sh-eval "case abc in a?c) echo q ;; esac") ())
```
---
    q

### ? does not match two characters

```sh
(do (sh-eval "case abcd in a?d) echo no ;; *) echo miss ;; esac") ())
```
---
    miss

### a character class matches a member

```sh
(do (sh-eval "case b in [abc]) echo cls ;; esac") ())
```
---
    cls

### a range class matches

```sh
(do (sh-eval "case m in [a-z]) echo range ;; esac") ())
```
---
    range

### a negated class excludes its members

```sh
(do (sh-eval "case d in [!abc]) echo neg ;; *) echo miss ;; esac") ())
```
---
    neg

### a negated class rejects a member

```sh
(do (sh-eval "case b in [!abc]) echo no ;; *) echo miss ;; esac") ())
```
---
    miss

### an exact pattern still matches exactly

```sh
(do (sh-eval "case abc in abd) echo no ;; abc) echo exact ;; esac") ())
```
---
    exact

## sh-eval reserved words in quotes

The body prints without a newline and the following command supplies the `:`,
so each case asserts ONE line: the harness compares the last line of a
snippet's output, and a two-line expectation would silently check only half of
what these are about.

### a quoted keyword in a while body does not open a block

```sh
(do (sh-eval "N=0; while test $N -eq 0; do echo -n \"while\"; N=1; done; echo :after") ())
```
---
    while:after

### a quoted keyword in an if body does not open a block

```sh
(do (sh-eval "if test a = a; then echo -n \"fi\"; fi; echo :after") ())
```
---
    fi:after

### a quoted keyword in a for body does not open a block

```sh
(do (sh-eval "for f in 1; do echo -n \"done\"; done; echo :after") ())
```
---
    done:after

### a quoted keyword in a skipped if branch does not open a block

```sh
(do (sh-eval "if false; then echo \"done\"; else echo -n taken; fi; echo :after") ())
```
---
    taken:after

### a quoted keyword in a case body does not open a block

```sh
(do (sh-eval "case a in a) echo -n \"esac\" ;; esac; echo :after") ())
```
---
    esac:after

## sh-eval reserved words as arguments

A reserved word is only reserved as the FIRST word of a command, and a closer
only closes when a construct is open — `echo done` at the top level used to
print a blank line AND silently discard the rest of the script.

### done is an ordinary argument at the top level

```sh
(do (sh-eval "echo done") ())
```
---
    done

### so is fi

```sh
(do (sh-eval "echo fi") ())
```
---
    fi

### and an opener like if

```sh
(do (sh-eval "echo if") ())
```
---
    if

### a stray closer does not swallow what follows

```sh
(do (sh-eval "echo done; echo after") ())
```
---
    after

### a real loop still closes on its done

```sh
(do (sh-eval "for f in 1; do echo -n loop; done; echo :after") ())
```
---
    loop:after

## sh-eval if without an else

An else-less `if` whose condition was FALSE had never parsed on any version of
this bundle: the skip consumed the `fi` that %eval-elif-chain then needed to
see, and every one of these was "parse error: expected elif, else, or fi".

### a false condition with no else runs nothing and continues

```sh
(do (sh-eval "if false; then echo A; fi; echo after") ())
```
---
    after

### a true condition still runs its body

```sh
(do (sh-eval "if true; then echo -n A; fi; echo :after") ())
```
---
    A:after

### an else-less if answers 0 when skipped

```sh
(sh-eval "if false; then echo A; fi")
```
---
    0

### a nested else-less if skips cleanly

```sh
(do (sh-eval "if false; then if true; then echo N; fi; fi; echo after") ())
```
---
    after

### elif still reached when the first condition fails

```sh
(do (sh-eval "if false; then echo A; elif true; then echo B; fi") ())
```
---
    B

### an else-less elif chain that all fails runs nothing

```sh
(do (sh-eval "if false; then echo A; elif false; then echo B; fi; echo after") ())
```
---
    after

### else still wins when every condition fails

```sh
(do (sh-eval "if false; then echo A; elif false; then echo B; else echo C; fi") ())
```
---
    C

## sh-eval skipping a branch that contains a compound

The five skip walks each carried their own copy of the opener and closer word
lists, and they had drifted: %skip-to-fi's openers were missing `until` and
`case` and its closers were missing `esac`. So a compound inside a branch the
parser SKIPS put the nesting count out by one. The first case below was
"parse error: unexpected EOF in if" until the lists became one.

### an until loop in a skipped else branch

```sh
(do (sh-eval "if true; then echo -n A; else until false; do echo B; done; fi; echo :after") ())
```
---
    A:after

### a case in a skipped else branch

```sh
(do (sh-eval "if true; then echo -n A; else case x in x) echo B ;; esac; fi; echo :after") ())
```
---
    A:after

### a while loop in a skipped else branch

```sh
(do (sh-eval "if true; then echo -n A; else while false; do echo B; done; fi; echo :after") ())
```
---
    A:after

### an until loop in a skipped then branch

```sh
(do (sh-eval "if false; then until false; do echo B; done; fi; echo after") ())
```
---
    after

### a nested if in a skipped else branch

```sh
(do (sh-eval "if true; then echo -n A; else if true; then echo B; fi; fi; echo :after") ())
```
---
    A:after

### a compound in a skipped case clause

```sh
(do (sh-eval "case b in a) until false; do echo X; done ;; b) echo -n B ;; esac; echo :after") ())
```
---
    B:after

## sh-eval the [ spelling of test

`[` has called an undefined `last` since 2024 — every `[ ... ]` answered
"Unbound SYMBOL 'last'". No spec reached it: the suite tested `test` and never
the bracket spelling of the same builtin.

### [ compares strings

```sh
(sh-eval "[ x = x ]")
```
---
    0

### and reports inequality

```sh
(sh-eval "[ x = y ]")
```
---
    1

### [ takes the file predicates

```sh
(sh-eval "[ -d / ]")
```
---
    0

### [ takes the numeric comparisons

```sh
(sh-eval "[ 3 -lt 5 ]")
```
---
    0

### [ works without its closing bracket

```sh
(sh-eval "[ x = x")
```
---
    0

### [ in a conditional

```sh
(do (sh-eval "if [ a = a ]; then echo yes; fi") ())
```
---
    yes
