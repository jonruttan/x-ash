## sh-eval read -d

`read -d DELIM` ends its line at DELIM's first byte rather than at a newline,
and `-d ''` at a NUL byte (POSIX 2024), so a newline in the input is data.
The status is 1 when the input ends before the delimiter, as it is for a line
with no newline.  `-d` clusters with `-r`, `-rd :`, and takes the rest of its
word, `-d:`.

Without `-r`, a backslash before the delimiter keeps the delimiter as data,
and a backslash before a newline still joins the lines.  POSIX leaves open
which of the two is the continuation.  A longer DELIM uses its first byte,
where POSIX leaves it open too.

Expectations follow BusyBox ash, the reference (shell/shell_common.c
`shell_builtin_read`), which reads each of these so; `/bin/sh` (bash 3.2)
agrees, and `dash` has no `-d`.  A case that holds on main as well is stated
as a pin.

### the line ends at the delimiter

```sh
(do (sh-eval "(printf 'a:b:c' | { read -d : x; echo \"st=$? x=[$x]\"; })") ())
```
---
    st=0 x=[a]

### input that ends first is still read, and answers 1

```sh
(do (sh-eval "(printf 'abc' | { read -d : x; echo \"st=$? x=[$x]\"; })") ())
```
---
    st=1 x=[abc]

### -d '' reads to a NUL byte

```sh
(do (sh-eval "(printf 'a\\0b\\0' | { read -r -d '' x; echo \"st=$? x=[$x]\"; })") ())
```
---
    st=0 x=[a]

### a newline is data

```sh
(do (sh-eval "(printf 'a\\nb:c' | { read -d : x; printf '%s' \"$x\" | tr '\\n' '|'; echo; })") ())
```
---
    a|b

### a backslash before the delimiter keeps it

```sh
(do (sh-eval "(printf 'a\\\\:b:c' | { read -d : x; echo \"x=[$x]\"; })") ())
```
---
    x=[a:b]

### a backslash before a newline still joins the lines

```sh
(do (sh-eval "(printf 'a\\\\\\nb:c' | { read -d : x; echo \"x=[$x]\"; })") ())
```
---
    x=[ab]

### -r keeps its backslashes

```sh
(do (sh-eval "(printf 'a\\\\x:b' | { read -r -d : x; echo \"x=[$x]\"; })") ())
```
---
    x=[a\x]

### -rd clusters, and the fields split as ever

```sh
(do (sh-eval "(printf 'a b:c' | { read -rd : x y; echo \"x=[$x] y=[$y]\"; })") ())
```
---
    x=[a] y=[b]

### -d takes the rest of its word

```sh
(do (sh-eval "(printf 'p:q:' | { read -d: x; echo \"x=[$x]\"; })") ())
```
---
    x=[p]

### a loop reads record by record

```sh
(do (sh-eval "(printf 'one:two:' | { while read -d : w; do printf '[%s]' \"$w\"; done; echo; })") ())
```
---
    [one][two]

### a longer delimiter uses its first byte

```sh
(do (sh-eval "(printf 'a:b:c' | { read -d ab x; echo \"st=$? x=[$x]\"; })") ())
```
---
    st=0 x=[]

### -d with a newline reads a line, as with no -d

```sh
(do (sh-eval "(printf 'a\\nb\\n' | { read -d '\n' x; echo \"x=[$x]\"; })") ())
```
---
    x=[a]

### pin: -d with nothing after it is a usage error

```sh
(do (sh-eval "(printf 'a:b' | { read -d 2>/dev/null; echo \"st=$?\"; })") ())
```
---
    st=2
