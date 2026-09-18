## sh-eval a case pattern is expanded, and its quoting kept

A case pattern is expanded as it is compared, the way any word is: a
parameter, a command substitution and arithmetic are read.  It is neither
split nor globbed against the filesystem, being one pattern rather than a
list of filenames.  Each is expanded when its turn comes, so in `a|$(cmd))`
the substitution runs only if `a` did not match.

What quoting makes literal stays literal to the matcher.  `"*"` is a star to
look for, not a star that matches anything; `"$p"` is the text `$p` holds,
wildcards and all, as characters.  An unquoted wildcard -- written or
expanded -- matches as a wildcard.

Expectations match `/bin/sh` and `dash`.

### a quoted piece is literal text

```sh
(do (sh-eval "case abc in \"a\"bc) echo ok;; *) echo no;; esac") ())
```
---
    ok

### a quoted star matches a star

```sh
(do (sh-eval "case '*' in \"*\") echo ok;; *) echo no;; esac") ())
```
---
    ok

### and nothing else

```sh
(do (sh-eval "case x in \"*\") echo no;; *) echo ok;; esac") ())
```
---
    ok

### an unquoted star matches anything

```sh
(do (sh-eval "case x in a* | *) echo ok;; esac") ())
```
---
    ok

### a parameter is expanded, and its wildcards match

```sh
(do (sh-eval "p='a*'; case abc in $p) echo ok;; *) echo no;; esac") ())
```
---
    ok

### a quoted parameter is its text

```sh
(do (sh-eval "p='a*'; case abc in \"$p\") echo no;; *) echo ok;; esac") ())
```
---
    ok

### which is a star, for a subject that has one

```sh
(do (sh-eval "p='a*'; case 'a*' in \"$p\") echo ok;; *) echo no;; esac") ())
```
---
    ok

### a substitution is expanded

```sh
(do (sh-eval "case abc in $(echo 'a*')) echo ok;; *) echo no;; esac") ())
```
---
    ok

### but only when its turn comes

```sh
(do (sh-eval "t=$(mktemp); case a in a|$(echo ran > \"$t\")) :;; esac; if [ -s \"$t\" ]; then echo expanded; else echo skipped; fi; rm -f \"$t\"") ())
```
---
    skipped

### which it does when the one before it fails

```sh
(do (sh-eval "t=$(mktemp); case b in a|$(echo ran > \"$t\"; echo b)) :;; esac; if [ -s \"$t\" ]; then echo expanded; else echo skipped; fi; rm -f \"$t\"") ())
```
---
    expanded

### single quotes keep everything

```sh
(do (sh-eval "case 'a$b' in 'a$b') echo ok;; *) echo no;; esac") ())
```
---
    ok

### a backslash escapes one character

```sh
(do (sh-eval "case 'a*c' in a\\*c) echo ok;; *) echo no;; esac") ())
```
---
    ok

### a quoted space is part of the pattern

```sh
(do (sh-eval "case 'a b' in \"a b\") echo ok;; *) echo no;; esac") ())
```
---
    ok

### a bracket class matches one of its characters

```sh
(do (sh-eval "case b in [abc]) echo ok;; *) echo no;; esac") ())
```
---
    ok
