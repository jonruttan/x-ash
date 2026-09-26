## sh-eval dollar-single-quotes

`$'...'` quotes its text as single quotes do, except that a backslash-escape
in it stands for a character: `$'a\tb'` is `a`, a tab and `b` (POSIX 2.2.4).
A `\'` does not close it.  It is one only outside quotes: inside double quotes
and in a here-document's body `$'` is two characters.

Expectations match `/bin/sh` (bash 3.2), and POSIX where they part: `\c?` is
delete, from the table POSIX gives `\cX`, where bash 3.2 keeps `\c?` as
written.  `dash` has no `$'...'`: it reads `$` and then a single quote, and
refuses `$'it\'s'` as an unterminated string.

Where POSIX gives an escape no value -- `\q`, or `\x` with no hex digit -- it
is kept as written, backslash and all, as bash keeps it.  A NUL byte ends the
text, as it ends it in bash; POSIX allows either that or keeping the NUL.

Bytes are compared as `od -An -tx1` writes them, with the spaces taken out.
Cases that hold on main as well are stated as pins.

### the letter escapes

```sh
(do (sh-eval "(printf '%s' $'\\a\\b\\e\\f\\n\\r\\t\\v\\\\\\'\\\"' | od -An -tx1 | tr -d ' \\n'; echo)") ())
```
---
    07081b0c0a0d090b5c2722

### \cX names a control character

```sh
(do (sh-eval "(printf '%s' $'\\cA\\cz\\c[\\c\\\\\\c?' | od -An -tx1 | tr -d ' \\n'; echo)") ())
```
---
    011a1b1c7f

### \x takes one or two hex digits, \ddd one to three octal ones

```sh
(do (sh-eval "(printf '%s' $'\\x41\\x4a\\x4g\\101\\060\\1' | od -An -tx1 | tr -d ' \\n'; echo)") ())
```
---
    414a0467413001

### an escape POSIX gives no value is kept as written

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

### a NUL byte ends the text

```sh
(do (sh-eval "(x=$'a\\0b'; echo \"${#x}\")") ())
```
---
    1

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
