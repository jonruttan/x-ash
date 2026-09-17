## sh-eval a backslash at the start of a word

Outside quotes a backslash protects the character after it wherever it stands
in a word, the first character included: `\;` is the word `;`, not a backslash
followed by the end of the command.  The same holds after a word's leading
digits, and inside a command substitution, where an escaped parenthesis
neither opens nor closes it.

Expectations match `/bin/sh` and `dash`.

### find's -exec ends at an escaped semicolon

```sh
(do (sh-eval "find /dev/null -prune -exec printf \"[%s]\" {} \\; ; echo") ())
```
---
    [/dev/null]

### every operator character can be escaped

```sh
(do (sh-eval "printf \"[%s]\" \\; \\| \\& \\< \\> \\( \\); echo") ())
```
---
    [;][|][&][<][>][(][)]

### and a two-character operator, one character at a time

```sh
(do (sh-eval "printf \"[%s]\" \\;\\; \\&\\& \\|\\| \\>\\>; echo") ())
```
---
    [;;][&&][||][>>]

### an escaped redirection redirects nothing

```sh
(do (sh-eval "d=$(mktemp -d); ( cd \"$d\"; printf \"[%s]\" \\>out; ls ); rm -rf \"$d\"; echo") ())
```
---
    [>out]

### an escaped blank starts a word

```sh
(do (sh-eval "printf \"[%s]\" \\ lead; echo") ())
```
---
    [ lead]

### an escaped quote or backquote is literal

```sh
(do (sh-eval "printf \"[%s]\" \\\"q\\\" \\'s\\' \\`b\\`; echo") ())
```
---
    ["q"]['s'][`b`]

### a word of digits takes an escape as well

```sh
(do (sh-eval "printf \"[%s]\" 1\\;2 12\\ 3; echo") ())
```
---
    [1;2][12 3]

### an escaped parenthesis does not end a command substitution

```sh
(do (sh-eval "printf \"[%s]\" \"$(echo \\))\" $(echo \\(); echo") ())
```
---
    [)][(]

### nor a backquoted one

```sh
(do (sh-eval "printf \"[%s]\" `echo \\)`; echo") ())
```
---
    [)]

### an escape inside a word is unchanged

```sh
(do (sh-eval "printf \"[%s]\" a\\;b x\\|\\|y; echo") ())
```
---
    [a;b][x||y]

### so is an escaped dollar or hash

```sh
(do (sh-eval "printf \"[%s]\" \\$HOME \\$\\(x\\) \\#x; echo") ())
```
---
    [$HOME][$(x)][#x]
