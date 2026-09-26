## sh-eval dollar-single-quotes

`$'...'` quotes its text as single quotes do, except that a backslash-escape
in it stands for a character: `$'a\tb'` is `a`, a tab and `b`.  A `\'` does not
close it.  It is one only outside quotes: inside double quotes and in a
here-document's body `$'` is two characters.

Expectations follow BusyBox ash, the reference (shell/ash.c
`decode_dollar_squote`, libbb/process_escape_sequence.c): the escapes are
`\" \' \\ \a \b \f \n \r \t \v`, `\xHH` and `\ddd`, and any other is kept as
written, backslash and all -- `\e` and `\cX` too, which POSIX 2024 names and
BusyBox does not.  An octal digit that would take the byte past 255 is read
and adds nothing.  A NUL byte is dropped and the text after it kept.

Bytes are compared as `od -An -tx1` writes them, with the spaces taken out.
Cases that hold on main as well are stated as pins.

### the letter escapes

```sh
(do (sh-eval "(printf '%s' $'\\a\\b\\f\\n\\r\\t\\v\\\\\\'\\\"' | od -An -tx1 | tr -d ' \\n'; echo)") ())
```
---
    07080c0a0d090b5c2722

### \e and \cX are kept as written, as BusyBox keeps them

```sh
(do (sh-eval "(printf '[%s]\\n' $'\\e\\cA')") ())
```
---
    [\e\cA]

### \x takes one or two hex digits, \ddd one to three octal ones

```sh
(do (sh-eval "(printf '%s' $'\\x41\\x4a\\x4g\\101\\060\\1' | od -An -tx1 | tr -d ' \\n'; echo)") ())
```
---
    414a0467413001

### an octal digit that would pass 255 is read and adds nothing

```sh
(do (sh-eval "(printf '%s' $'\\400x' | od -An -tx1 | tr -d ' \\n'; echo)") ())
```
---
    2078

### an escape that names nothing is kept as written

```sh
(do (sh-eval "(printf '[%s]\\n' $'\\q\\xz')") ())
```
---
    [\q\xz]

### the text is quoted: not split and not a pattern

```sh
(do (sh-eval "(set -- $'a b' $'*'; echo \"$# $2\")") ())
```
---
    2 *

### \' does not close it, and the word goes on around it

```sh
(do (sh-eval "(echo $'it\\'s' x$'y'z)") ())
```
---
    it's xyz

### an empty one is an empty field

```sh
(do (sh-eval "(set -- $''; echo $#)") ())
```
---
    1

### a NUL byte is dropped and the text after it kept

```sh
(do (sh-eval "(x=$'a\\0b'; echo \"${#x} $x\")") ())
```
---
    2 ab

### bytes above 127 are bytes

```sh
(do (sh-eval "(x=$'\\x80\\xff'; printf '%s' \"$x\" | od -An -tx1 | tr -d ' \\n'; echo)") ())
```
---
    80ff

### one inside a command substitution is read there

```sh
(do (sh-eval "(x=\"$(printf '%s' $'q\\'')\"; echo \"$x\")") ())
```
---
    q'

### a continued line around one is still joined

```sh
(do (sh-eval "(echo $'a\\tb' \\\nc | od -An -tx1 | tr -d ' \\n'; echo)") ())
```
---
    61096220630a

### a here-document after one on its line is still found

```sh
(do (sh-eval "(printf '[%s]' $'a\\'b <<X' <<EOF\nbody\nEOF\necho end)") ())
```
---
    [a'b <<X]end

### the prompt does not wait for more after one holding \'

```sh
(write (%ash-complete? "echo $'it\\'s'"))
```
---
    #t

### pin: inside double quotes $' is two characters

```sh
(do (sh-eval "(echo \"$'a'\")") ())
```
---
    $'a'

### pin: $$ before a single quote is the parameter

```sh
(do (sh-eval "(x=$$'y'; [ \"$x\" = \"$$y\" ] && echo ok)") ())
```
---
    ok

### pin: an escaped $ opens nothing

```sh
(do (sh-eval "(echo \\$'a')") ())
```
---
    $a

### pin: in a here-document's body it is text

```sh
(do (sh-eval "(cat <<EOF\n$'a\\tb'\nEOF\n)") ())
```
---
    $'a\tb'
