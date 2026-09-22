## sh-eval where an expansion's error is written

An expansion that fails -- an unset parameter under `set -u`, a `${X?word}`,
a bad substitution, arithmetic that is no expression -- writes its message to
the standard error in force where it happens: a subshell's, a pipeline
stage's, a command substitution's.  ash wrote it where the raise was caught
instead, by which point the shell's own standard error was back, so the
message went past the redirection.

A simple command's own redirections are not in force yet, a word being
expanded before they are applied, so `echo "$X" 2>/dev/null` still shows the
message.  Both shells do that too.

Expectations match `/bin/sh` and `dash` but for the message's wording, where
the two differ: each case keeps what follows the last `: `, which is dash's
wording and ash's.

### in a command substitution

```sh
(do (sh-eval "( set -u; r=$( { echo \"$zz\"; } 2>&1 ); echo \"[${r##*: }]\" )") ())
```
---
    [parameter not set]

### in a subshell

```sh
(do (sh-eval "( set -u; r=$( ( echo \"$zz\" ) 2>&1 ); echo \"[${r##*: }]\" )") ())
```
---
    [parameter not set]

### in a pipeline stage

```sh
(do (sh-eval "( set -u; { echo \"$zz\"; } 2>&1 | tail -1 | sed 's/^.*: //' )") ())
```
---
    parameter not set

### the word of `${X?word}`

```sh
(do (sh-eval "( r=$( { echo \"${zz?msg}\"; } 2>&1 ); echo \"[${r##*: }]\" )") ())
```
---
    [msg]

### the failing command's own redirection does not take it

```sh
(do (sh-eval "( set -u; r=$( { echo \"$zz\" 2>/dev/null; } 2>&1 ); echo \"[${r##*: }]\" )") ())
```
---
    [parameter not set]

### arithmetic that is no expression

```sh
(do (sh-eval "( r=$( { echo \"$((1 2))\"; } 2>&1 ); case \"$r\" in \"\") echo empty;; *) echo message;; esac )") ())
```
---
    message

### a bad substitution

```sh
(do (sh-eval "( r=$( { echo \"${1a}\"; } 2>&1 ); case \"$r\" in *'ad substitution'*) echo BAD;; \"\") echo empty;; *) echo other;; esac )") ())
```
---
    BAD
