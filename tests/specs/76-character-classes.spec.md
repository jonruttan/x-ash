## sh-eval POSIX character classes in a bracket expression

A bracket expression may name a class: `[[:digit:]]` is one digit,
`[[:alpha:]_]` a letter or an underscore, `[![:space:]]` anything but white
space.  The twelve names are POSIX's -- alnum, alpha, blank, cntrl, digit,
graph, lower, print, punct, space, upper, xdigit -- read in the C locale, and a
name that is not one of them matches nothing.  The class is stepped over whole
when the bracket's end is looked for, so its own `]` does not close the
expression.

Patterns are one matcher, so this holds in a `case`, in `${x#pattern}` and in
pathname expansion alike.  A `[:` with no `:]` is left undefined by POSIX,
and the reference shells read `[[:alpha]` differently from each other; here
its characters are simply members of the bracket.

Expectations match `/bin/sh` and `dash`, but for the table, which asks the
matcher itself and was checked against `/bin/sh` class by class.

### alpha in a case

```sh
(do (sh-eval "case a in [[:alpha:]]) echo alpha;; *) echo other;; esac") ())
```
---
    alpha

### digit, and the rest of the word after it

```sh
(do (sh-eval "case 42x in [[:digit:]]*) echo leads;; *) echo not;; esac") ())
```
---
    leads

### negated

```sh
(do (sh-eval "for w in a5 5a _x; do case $w in [![:digit:]]*) printf '%s:yes ' $w;; *) printf '%s:no ' $w;; esac; done; echo") ())
```
---
    a5:yes 5a:no _x:yes 

### beside other members

```sh
(do (sh-eval "case _ in [[:alpha:]_]) echo ok;; *) echo no;; esac") ())
```
---
    ok

### two classes in one bracket

```sh
(do (sh-eval "for c in a 5 -; do case $c in [[:alpha:][:digit:]]) printf 'y';; *) printf 'n';; esac; done; echo") ())
```
---
    yyn

### space in parameter expansion

```sh
(do (sh-eval "x='  pad'; echo \"[${x#[[:space:]]}]\" \"[${x##*[[:space:]]}]\"") ())
```
---
    [ pad] [pad]

### upper and lower

```sh
(do (sh-eval "for c in A a; do case $c in [[:upper:]]) printf U;; [[:lower:]]) printf L;; esac; done; echo") ())
```
---
    UL

### xdigit

```sh
(do (sh-eval "for c in f F g 9; do case $c in [[:xdigit:]]) printf y;; *) printf n;; esac; done; echo") ())
```
---
    yyny

### punct

```sh
(do (sh-eval "for c in ! _ a 1; do case \"$c\" in [[:punct:]]) printf y;; *) printf n;; esac; done; echo") ())
```
---
    yynn

### in pathname expansion

```sh
(do (sh-eval "d=$(mktemp -d); cd \"$d\"; : > a1 > b2 > 3c; echo [[:alpha:]]*; cd /; rm -rf \"$d\"") ())
```
---
    a1 b2

### each class against a spread of characters

```sh
(do
  (write
    (map (fn (_ cls)
           (list->string
             (filter (fn (_ c) (%sh-pattern-match? (string-append "[[:" cls ":]]")
                                                   (list->string (list c))))
               (list #\a #\Z #\5 #\_ #\space #\! #\f #\G #\- #\~))))
      (list "alpha" "digit" "alnum" "upper" "lower" "space" "blank" "punct"
            "print" "graph" "xdigit" "bogus")))
  ())
```
---
    ("aZfG" "5" "aZ5fG" "ZG" "af" " " " " "_!-~" "aZ5_ !fG-~" "aZ5_!fG-~" "a5f" "")
