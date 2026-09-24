## sh-eval an arithmetic operand where none stands

An arithmetic expression is refused when an operand is missing: the text ends
where one should stand, or the character there starts none, or a `(` has no
`)`.  A branch that is not taken is still read, so a missing operand there is
refused too.  The empty expression has no operand, and is refused as well.

Expectations match `/bin/sh` and `dash`, except where noted.  The second case
is a pin that holds on main too.

### a missing operand, an unknown character, an unclosed paren

Each expression is its own `eval` in a subshell, so each refusal ends only
that subshell; an `r` is written for each one refused.

```sh
(do (sh-eval "( for e in '1 +' '- ' '1 + @' '1 ? 2' 'x = ' '()' '1 ? 2 : ' '!' '~' '1 *' '1 <<' '+' '1 ? : 3' '0 && (1 +)' '1 || @' '(1 2)'; do ( eval \"echo \\$(( $e ))\" ) 2>/dev/null || printf 'r'; done; echo )") ())
```
---
    rrrrrrrrrrrrrrrr

### what only looks like one is read

```sh
(do (sh-eval "( echo $(( 1 +  2 )) $(( (1) )) $(( -(1) )) $(( 1 +-2 )) $(( 1 - -2 )) $(( --1 )) $(( (1) + 2 )) $(( 0 && (1 + 2) )) )") ())
```
---
    3 1 -1 -1 3 1 3 0

### the empty expression

`dash` refuses it, as it refuses any missing operand; bash answers 0.

```sh
(do (sh-eval "( ( eval 'echo $(( ))' ) 2>/dev/null || echo refused )") ())
```
---
    refused

### an expression a variable left empty

The same reading, after expansion: `dash` refuses it, bash answers 0.

```sh
(do (sh-eval "( x=; ( eval 'echo $(( $x ))' ) 2>/dev/null || echo refused )") ())
```
---
    refused
