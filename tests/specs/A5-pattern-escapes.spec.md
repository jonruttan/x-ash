## sh-eval a backslash in an expanded pattern

A pattern -- a `case` pattern, the operand of `${x#pat}` and the other trims
-- is expanded without splitting, and a backslash an unquoted expansion's
value holds escapes the character after it, as a backslash written in the
pattern does: with p='a\*', `${x#$p}` removes a literal `a*`.  A backslash
left at the end of a pattern escapes nothing, and the pattern matches nothing.
Quoted, the value is literal, backslash and all.  Outside a pattern a value's
backslash is an ordinary character, as it was.

Expectations match `/bin/sh` and `dash`.

### a trim's pattern

```sh
(do (sh-eval "( p='a\\*'; x='a*b'; echo \"${x#$p}\" )") ())
```
---
    b

### as a backslash written there

```sh
(do (sh-eval "( p='\\*'; x='*b'; echo \"${x#$p}\" \"${x#\\*}\" )") ())
```
---
    b b

### an escaped backslash

```sh
(do (sh-eval "( p='\\\\'; x='a\\b'; echo \"${x%$p*}\" )") ())
```
---
    a

### a case pattern

```sh
(do (sh-eval "( p='a\\*'; case 'a*' in $p) echo yes;; *) echo no;; esac )") ())
```
---
    yes

### the word of a value operator, in a pattern

```sh
(do (sh-eval "( p='a\\*'; x='a*b'; r=no; case 'a*' in ${u:-$p}) r=yes;; esac; echo \"${x#${u:-$p}} $r\" )") ())
```
---
    b yes

### the parameters, in a pattern

```sh
(do (sh-eval "( IFS=; set -- 'a\\*'; x='a*b'; echo \"${x#$*}\" )") ())
```
---
    b

### a backslash at a pattern's end escapes nothing, and nothing matches

```sh
(do (sh-eval "( p='a\\'; r=no; case 'a\\' in $p) r=yes;; esac; q='\\'; x='a\\'; echo \"${x%$q} $r\" )") ())
```
---
    a\ no

### quoted, the value is literal

```sh
(do (sh-eval "( x='a*b'; y='a\\*'; echo \"${x#\"$y\"}\" )") ())
```
---
    a*b

### an escaped wildcard matches only itself

```sh
(do (sh-eval "( p='\\*'; case a in a$p) echo yes;; *) echo no;; esac )") ())
```
---
    no

### outside a pattern a backslash is a character

```sh
(do (sh-eval "( x='a\\*'; set -- $x; y='a\\b'; z=$y; printf '%s %s\\n' \"$1\" \"$z\" )") ())
```
---
    a\* a\b
