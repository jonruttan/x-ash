## sh-eval here-documents among quotes

Here-documents are found in the raw text before it is read, by a scan that
keeps its place from one line to the next: inside a quoted string `<<` is
text, and inside a `$(` it is an operator again, even when the `$(` is inside
double quotes.  A string or a `$(` can run past the end of a line.  A
backslash takes the character after it, and a `#` where a word could start is
a comment to the end of its line.

Expectations match `/bin/sh` and `dash`.

### a here-document inside a quoted command substitution

```sh
(do (sh-eval "( x=\"$(cat <<EOF\nhello\nEOF\n)\"; echo \"$x\"\n)") ())
```
---
    hello

### its body expands

```sh
(do (sh-eval "( v=val; x=\"$(cat <<EOF\ngot $v\nEOF\n)\"; echo \"$x\"\n)") ())
```
---
    got val

### as an argument

```sh
(do (sh-eval "( echo \"$(cat <<EOF\nin quotes\nEOF\n)\"\n)") ())
```
---
    in quotes

### inside a subshell inside the substitution

```sh
(do (sh-eval "( x=\"$( (cat <<EOF\nsub\nEOF\n) )\"; echo \"$x\"\n)") ())
```
---
    sub

### inside nested substitutions

```sh
(do (sh-eval "( x=\"$(echo \"$(cat <<EOF\ndeep\nEOF\n)\")\"; echo \"$x\"\n)") ())
```
---
    deep

### on the line a multi-line string ends on

```sh
(do (sh-eval "( x=\"line1\nline2\"; while read -r l; do echo \"<$l>\"; done <<EOF\n$x\nEOF\n)") ())
```
---
    <line2>

### inside a multi-line single-quoted string it is text

```sh
(do (sh-eval "( x='a\nb <<c'; echo \"$x\" | tail -1\n)") ())
```
---
    b <<c

### after an escaped quote

```sh
(do (sh-eval "( echo it\\'s; cat <<EOF\nescaped\nEOF\n)") ())
```
---
    escaped

### an apostrophe in a comment opens no string

```sh
(do (sh-eval "( # it's a comment\ncat <<EOF\nafter comment\nEOF\n)") ())
```
---
    after comment

### a shift in a quoted arithmetic expansion stays a shift

```sh
(do (sh-eval "( echo \"$((1<<2))\" && cat <<EOF\nafter\nEOF\n)") ())
```
---
    after
