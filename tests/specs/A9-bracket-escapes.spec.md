## sh-eval a backslash inside a bracket expression

Inside `[...]` a backslash makes the character after it a member, itself and
nothing else: `[a\]]` holds `]`, which therefore closes nothing, and `[a\-z]`
holds a literal `-` rather than the range `a` to `z`.  A member either side of
a `-` may be escaped too, so `[\a-c]` is still the range `a` to `c`.

Expectations match `/bin/sh` and `dash`.  Three readings differ between the
two, and ash takes `/bin/sh`'s: `[a\]]` against `a`, the unterminated `[a\]`,
and `[^\]]` against `]`.

`T` prints its third argument and whether the pattern matched the word.

### an escaped `]` is a member

```sh
(do (sh-eval "( T() { case \"$2\" in $1) printf '[%s=y]' \"$3\";; *) printf '[%s=n]' \"$3\";; esac; }; T '[a\\]]' ']' one; T '[a\\]]' ']]' two; T '[]a]' ']' three; echo )") ())
```
---
    [one=y][two=n][three=y]

### an escaped `-` is a member, and not a range

```sh
(do (sh-eval "( T() { case \"$2\" in $1) printf '[%s=y]' \"$3\";; *) printf '[%s=n]' \"$3\";; esac; }; T '[a\\-z]' '-' dash; T '[a\\-z]' 'b' mid; T '[a\\-z]' 'z' end; T '[\\-]' '-' alone; echo )") ())
```
---
    [dash=y][mid=n][end=y][alone=y]

### a range whose first member is escaped

```sh
(do (sh-eval "( T() { case \"$2\" in $1) printf '[%s=y]' \"$3\";; *) printf '[%s=n]' \"$3\";; esac; }; T '[\\a-c]' 'b' inside; T '[\\a-c]' 'd' outside; echo )") ())
```
---
    [inside=y][outside=n]

### a negated class with one

```sh
(do (sh-eval "( T() { case \"$2\" in $1) printf '[%s=y]' \"$3\";; *) printf '[%s=n]' \"$3\";; esac; }; T '[!\\]]' ']' closer; T '[!\\]]' 'x' other; echo )") ())
```
---
    [closer=n][other=y]

### a backslash of its own

```sh
(do (sh-eval "( T() { case \"$2\" in $1) printf '[%s=y]' \"$3\";; *) printf '[%s=n]' \"$3\";; esac; }; T '[\\\\]' '\\' member; T '[a\\]' '\\' unclosed; echo )") ())
```
---
    [member=y][unclosed=n]

### a trim's pattern reads them the same way

```sh
(do (sh-eval "( x='a]b'; p='[a\\]]'; y=']z'; echo \"${x%%[\\]]*} ${y#$p}\" )") ())
```
---
    a z

### what a class held before

```sh
(do (sh-eval "( T() { case \"$2\" in $1) printf '[%s=y]' \"$3\";; *) printf '[%s=n]' \"$3\";; esac; }; T '[a-c]' 'b' range; T '[!a-c]' 'd' negated; T '[[:digit:]]' '5' named; T '[[:alpha:]0]' '0' mixed; T '[a-]' '-' trailing; echo )") ())
```
---
    [range=y][negated=y][named=y][mixed=y][trailing=y]
