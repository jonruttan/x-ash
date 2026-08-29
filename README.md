# x-ash — a POSIX shell on x-lang

A shell: its own tokenizer on its own base, word expansion, redirection,
pipelines, and the control structures.

```
$ x -l ash
$ echo hello | grep h
hello
$ for f in a b c; do echo $f; done
a
b
c
```

## Status

**80 of 82 specs green** against x-lang **v0.6.0** and an x-engine-c carrying the
[#528](https://github.com/jonruttan/x-lang/issues/528) fix.

Last of the five 2024-era langs to come back, the largest, and the only
one that is not a Lisp. It is also the only one that was blocked on an engine
bug rather than on drift — see below.

The 2 that do not pass are the single- and double-quoted string readers: `''`
tokenizes correctly and `'a'` loses its accumulator, so the closing quote sees
an empty one. That is in how the tokenizer drives a state that scores nothing
on entry, and it wants someone reading the C token loop rather than more
guessing from outside.

## Running it

```bash
make test        # the spec suite
make install     # into the x on PATH
```

then `x -l ash`. `make install` puts the bundle where `-l` looks — an installed
x searches `<share>/langs/*/lang.xon`, so a lang is installed when its files
are there. No registry, no per-project pin. Use `lang.pin.xon` and `Pin bundle`
instead when it matters which version.

## Layout

```
lang.xon          name, dialect, release pairing
run.x             THE entry -- and it knows no paths at all
ash/prims.x       the platform layer, under the names ash was written against
ash/tokens.x      shell token types, on an isolated tokenizer base
ash/eval.x        parser and evaluator in one pass
ash/printer.x     a shell shows what the command printed
```

`lib/parser.x` from the 2024 tree is not here. `eval.x`'s own header says it
"replaces parser.x + old eval.x", and nothing loaded parser.x then either;
carrying 389 lines of superseded recursive descent into a new bundle would be
carrying a fossil.

## The architecture survived; the engine had not

ash tokenizes shell syntax on a **separate base with its own type alist**, so
`;` can be a separator rather than a comment and `#` a comment rather than a
dispatch character. In 2024 that needed `make-token-base` and
`base-make-type`, and the obvious reading of their disappearance is that the
platform stopped supporting isolated tokenizer bases.

It did not. They are `(Base make-tok)` and `(Base make-type)`, and `make-tok`
documents itself as being "for custom tokenizer type registration on an
isolated base" — so the single most unusual thing in this bundle is still
first-class.

It also segfaulted on the first character of any input. `x_prim_make_token_base`
assigned to `x_eval_field_true(p_new)` where `x-eval-layout.h` marks that field
a *cell* and `x_eval_make`'s own parented path writes through it, so each cell
was replaced by the singleton it should have contained; and it never created a
read buffer, which `make_base` does. Fixed in the engine
([#528](https://github.com/jonruttan/x-lang/issues/528)), which took this bundle
from dead at load to 80/82.

**It presented as radon-only**, which sent me the wrong way for a while. It is
not the dialect — it is collection pressure. radon simply allocates more at
boot, so a collect lands in the wrong place without anyone asking for one. Force
one under xenon and the shipped engine fails identically.

## What porting it cost

`ash/prims.x` is the whole of it. Everything the shell needs from the platform
moved onto classes since 2024, and none of it moved far: `sh-fork`, `sh-dup2`,
`sh-open-read` and the rest are one-line forwards to `Sys`, which carries every
one under a name a shell would recognise.

**Every `fn` needed a receiver.** 102 of them across `tokens.x` and `eval.x` —
x's `fn` takes an explicit `_`, so each was binding its first real parameter to
the receiver. Mechanical, and the same defect as `(def lambda fn)` in x-r5rs.

**Three bugs were mine, and they rhyme.** Each was a convenient spelling that
allocates inside a reader callback — where `lib/x/reader/analyser.x` says
outright that class dispatch is "hazardous mid-reader-callback":

- `char->integer` as `(convert c %int)` goes through the *dispatcher*, and
  `%sh-word-break?` calls it six times **per character**. Registering SH-WORD
  was enough to kill `(sh-tokenize " ")`. The cached
  `(prim-ref (lit char) (lit ->int))` is the spelling analyser.x itself holds.
- `(prim-ref (lit char) (lit from-int))` **does not exist** — conversions are
  keyed on the *source* type, so it is `(int ->char)`. `prim-ref` answers nil
  for a missing member, which reached the reader as a garbage integer rather
  than an error.
- `reverse` as `(List reverse …)` is a class dispatch, called at a closing
  quote. `''` tokenized fine; `'a'` silently produced an empty accumulator.

The middle one is the one to watch: a `prim-ref` miss is indistinguishable from
a legitimate nil until it surfaces somewhere far away.

## Licence

MIT No Attribution (MIT-0). See [LICENSE](LICENSE).
