## sh-eval the regions a word is read in

A word that is not one plain run is walked region by region: a quoted run, a
backslash and what it protects, an expansion, a tilde at the front, and the
plain runs between them.  Each of those is one arm of the walk, and these
cases hold them where the rest of the suite reads them one at a time.

Expectations match `/bin/sh` and `dash`.  They hold on main too: the walk
answers what it answered, for less.

### quotes, escapes, expansions and a tilde

```sh
(do (sh-eval "( x=v; HOME=/h; set -- \"a'b'c\" a\\ b \"\\$x\" \"$x\" ~ ~/y \"p${x}s\" `echo bt`; printf \"[%s]\" \"$@\"; echo )") ())
```
---
    [a'b'c][a b][$x][v][/h][/h/y][pvs][bt]

### a quoted region either side of an expansion

```sh
(do (sh-eval "( x=v; set -- 'a'\"$x\"'b' \"'\" '\"'; printf \"[%s]\" \"$@\"; echo )") ())
```
---
    [avb][']["]

### a backslash at a word's end, and in and out of quotes

```sh
(do (sh-eval "( set -- a\\\\ \"a\\\\b\" \"a\\$b\" 'a\\b'; printf \"[%s]\" \"$@\"; echo )") ())
```
---
    [a\][a\b][a$b][a\b]
