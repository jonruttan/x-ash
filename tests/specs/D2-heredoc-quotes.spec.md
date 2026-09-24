## sh-eval double quotes in a here-document

An unquoted here-document's body is expanded as a double-quoted string is,
except that `"` is ordinary text there (POSIX 2.7.4): it is written as it
stands, and a backslash before it stays.  A backslash still escapes `$`, a
backquote, a backslash and a newline, and quotes inside `${ }`, `$( )` and
backquotes are still quotes.  The body is one text, so `$@` is the parameters
joined as `$*` joins them.  An arithmetic expression reads the same way (POSIX
2.6.4), so a `"` in one is no operand.

Expectations match `/bin/sh` and `dash`, except where noted.  The fourth case
is a pin that holds on main too.

### quotes and backslashes in the body

```sh
(do (sh-eval "( x=v; cat <<E\na \"q\" b\n\\\"bs-quote\\\" \\$x \\\\ \\`\n\"$x\" ${x} \"$(echo \"in\")\" `echo \"bt\"`\n's' \\a\nE\n) | tr '\\n' '|'; echo") ())
```
---
    a "q" b|\"bs-quote\" $x \ `|"v" v "in" bt|'s' \a|

### `$@` and `$*` in the body

```sh
(do (sh-eval "( set -- a \"b c\"; cat <<E\n[$@] [$*] [${1}]\nE\n)") ())
```
---
    [a b c] [a b c] [a]

### joined on IFS's first character

`dash` joins both on it; bash joins `$*` on a space here.

```sh
(do (sh-eval "( IFS=:; set -- a b; cat <<E\n[$@] [$*]\nE\n)") ())
```
---
    [a:b] [a:b]

### quotes inside `${ }` are quotes

```sh
(do (sh-eval "( unset u; cat <<E\n[${u:-\"quoted word\"}] [${u:-'single'}]\nE\n)") ())
```
---
    [quoted word] ['single']

### a `"` in an arithmetic expression is no operand

```sh
(do (sh-eval "( ( eval 'echo $(( \"1\" + 2 ))' ) 2>/dev/null || echo refused )") ())
```
---
    refused
