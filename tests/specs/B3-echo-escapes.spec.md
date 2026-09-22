## sh-eval `echo` and its backslash escapes

`echo` reads a backslash in its operands as XSI has it: `\a \b \f \n \r \t
\v` and `\\` are those characters, `\0` with up to three octal digits after it
is the byte they make, and `\c` ends the output where it stands, newline and
all.  Any other backslash is itself, and an operand that looks like an option
is an operand -- `-e`, `-E`, `--`, `-nn` -- but for a first `-n`, which leaves
the newline off.

Expectations match `/bin/sh` and `dash`.  Where the two part, ash reads `-n`
as dash does and `\NNN` without its `0`, and `\xHH`, as the text POSIX leaves
them.  A string cannot hold a NUL byte here, so `\0` making 0 writes nothing.

### a newline and a tab

```sh
(do (sh-eval "( echo 'a\\nb\\tc' | tr '\\n\\t' 'NT'; echo )") ())
```
---
    aNbTcN

### `\c` ends the output, the operands after it and the newline too

```sh
(do (sh-eval "( echo 'x' 'a\\cb' 'y'; echo '|' )") ())
```
---
    x a|

### a backslash that names nothing is itself

```sh
(do (sh-eval "( echo 'a\\\\b' 'a\\qb' 'a\\eb' 'trail\\' )") ())
```
---
    a\b a\qb a\eb trail\

### an octal byte

```sh
(do (sh-eval "( echo 'a\\0101b'; [ \"$(echo 'a\\0777b')\" = \"$(printf 'a\\377b')\" ] && echo same || echo differ )") ())
```
---
    same

### the control characters

```sh
(do (sh-eval "( [ \"$(echo 'a\\ab\\bc\\fd\\ve\\rf')\" = \"$(printf 'a\\ab\\bc\\fd\\ve\\rf')\" ] && echo same || echo differ )") ())
```
---
    same

### operands that look like options

```sh
(do (sh-eval "( r=$(echo -e a; echo -E b; echo -- c; echo -nn d); echo $r )") ())
```
---
    -e a -E b -- c -nn d

### a value's escapes are read as well

```sh
(do (sh-eval "( x='1\\n2'; echo $x | tr '\\n' 'N'; echo )") ())
```
---
    1N2N
