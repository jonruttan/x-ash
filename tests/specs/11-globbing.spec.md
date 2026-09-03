## sh-glob splitting and escaping

### a pattern splits on unescaped slashes

```sh
(write (%sh-glob-split "a/b/c"))
```
---
    ("a" "b" "c")

### an escaped slash does not split

```sh
(write (%sh-glob-split "a\\/b"))
```
---
    ("a\\/b")

### a trailing slash leaves an empty last segment

```sh
(write (%sh-glob-split "a/"))
```
---
    ("a" "")

### an unescaped star makes it a pattern

```sh
(write (%sh-glob-pattern? "a*b"))
```
---
    #t

### an escaped star does not

```sh
(write (%sh-glob-pattern? "a\\*b"))
```
---
    ()

### ? and [ also make it a pattern

```sh
(write (list (%sh-glob-pattern? "a?b") (%sh-glob-pattern? "a[b")))
```
---
    (#t #t)

### unescaping takes one backslash off

```sh
(write (%sh-glob-unescape "a\\*b\\?c"))
```
---
    "a*b?c"

### text with no backslash is its own unescaping

```sh
(write (%sh-glob-unescape "abc"))
```
---
    "abc"

### a dotfile is invisible to a pattern that does not start with a dot

```sh
(write (list (%sh-glob-visible? "*" ".hidden") (%sh-glob-visible? ".*" ".hidden")))
```
---
    (#f #t)

### joining onto the empty base keeps the path relative

```sh
(write (list (%sh-path-join "" "a") (%sh-path-join "/" "a") (%sh-path-join "/x" "a")))
```
---
    ("a" "/a" "/x/a")

## sh-glob matching the filesystem

### a pattern that matches answers the path

```sh
(write (%sh-glob-field "/de?"))
```
---
    ("/dev")

### a literal path is left alone

```sh
(write (%sh-glob-field "/dev/null"))
```
---
    ("/dev/null")

### a pattern that matches nothing stands as written

```sh
(write (%sh-glob-field "/nosuchthing-ash*"))
```
---
    ("/nosuchthing-ash*")

### a star matches within a directory

```sh
(write (%sh-glob-field "/de*"))
```
---
    ("/dev")

### a two-level pattern walks down

Globbing a large directory is expensive enough to matter to the suite -- see
the SPEC_BATCH note in tests/spec-runner.sh -- so exactly one case listens to a
big one, and the rest match against `/`.

```sh
(write (%sh-glob-field "/dev/nul?"))
```
---
    ("/dev/null")

### globbing reaches the command line

```sh
(do (sh-eval "echo /de?") ())
```
---
    /dev

## sh-eval quoting suppresses globbing

### double quotes keep the star literal

```sh
(do (sh-eval "echo \"*\"") ())
```
---
    *

### single quotes keep the star literal

```sh
(do (sh-eval "echo '*'") ())
```
---
    *

### a backslash keeps the star literal

```sh
(do (sh-eval "echo \\*") ())
```
---
    *

### a quoted pattern that would otherwise match stays literal

```sh
(do (sh-eval "echo \"/de?\"") ())
```
---
    /de?

### an unquoted expansion IS globbed

```sh
(do (sh-eval "P=/de?; echo $P") ())
```
---
    /dev

### a quoted expansion is not

```sh
(do (sh-eval "P=/de?; echo \"$P\"") ())
```
---
    /de?

### a non-matching pattern reaches the command as itself

```sh
(do (sh-eval "echo /nosuchthing-ash*") ())
```
---
    /nosuchthing-ash*

### a redirection target is not split or globbed

```sh
(do (sh-eval "echo written > /dev/null; echo ok") ())
```
---
    ok
