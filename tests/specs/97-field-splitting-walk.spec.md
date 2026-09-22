## sh-eval field splitting, walked by index

An unquoted expansion is split into fields by one walk over its text by
index, each field cut out once when it ends.  IFS whitespace around a
delimiter goes with it and never makes an empty field; a delimiter that is
not whitespace ends a field whatever it holds, so two in a row make an empty
one, and a leading one makes an empty first field while a trailing one makes
none.

Expectations match `/bin/sh` and `dash`.

### a long field is one field

```sh
(do (sh-eval "( x=$(printf '%0300d' 0); set -- $x; echo \"$# ${#1}\" )") ())
```
---
    1 300

### many fields

```sh
(do (sh-eval "( x=\"a b c d e f g h i j\"; set -- $x; echo \"$# $1$10\" )") ())
```
---
    10 aa0

### two hard delimiters make an empty field

```sh
(do (sh-eval "( IFS=:; x=\"a::b\"; set -- $x; echo \"$#:$1:$2:$3\" )") ())
```
---
    3:a::b

### a leading one makes an empty first field, a trailing one none

```sh
(do (sh-eval "( IFS=:; x=\":a:\"; set -- $x; echo \"$#:[$1]:[$2]\" )") ())
```
---
    2:[]:[a]

### whitespace around a hard delimiter goes with it

```sh
(do (sh-eval "( IFS=': '; x=\" a : b  :c \"; set -- $x; echo \"$#:[$1][$2][$3]\" )") ())
```
---
    3:[a][b][c]

### whitespace alone makes no empty field

```sh
(do (sh-eval "( IFS=': '; x=\"a  b\"; set -- $x; echo \"$#\" )") ())
```
---
    2

### a comma list with a gap and a trailing comma

```sh
(do (sh-eval "( IFS=,; x=\"1,,2,\"; set -- $x; echo \"$#:[$1][$2][$3]\" )") ())
```
---
    3:[1][][2]

### blanks alone are no fields

```sh
(do (sh-eval "( x=\"   \"; set -- $x; echo \"$#\" )") ())
```
---
    0

### leading blanks are skipped

```sh
(do (sh-eval "( x=\"  lead\"; set -- $x; echo \"$#:[$1]\" )") ())
```
---
    1:[lead]

### two hard delimiters alone

```sh
(do (sh-eval "( IFS=:; x=\"::\"; set -- $x; echo \"$#\" )") ())
```
---
    2

### lines of a substitution

```sh
(do (sh-eval "( x=$(printf 'l1\\nl2\\nl3'); set -- $x; echo \"$#:$3\" )") ())
```
---
    3:l3

### a tab is no delimiter when IFS is a space

```sh
(do (sh-eval "( IFS=' '; x=$(printf 'a\\tb'); set -- $x; echo \"$#\" )") ())
```
---
    1
