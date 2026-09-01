# x-ash — a POSIX shell on x-lang

A shell on [x-lang](https://github.com/jonruttan/x-lang): its own tokenizer on its own base, word
expansion, redirection, pipelines, and the control structures.

```
$ x -l ash
$ echo hello | grep h
hello
$ for f in a b c; do echo $f; done
a
b
c
```

x-ash is a **lang**: a different surface language loaded over an x-lang
dialect. Where x-lang and ash spell something the same way, ash is free to mean
something different by it — `;` separates commands here rather than starting a
comment, and `#` starts one rather than dispatching. It is the only one of the
five that is not a Lisp, and the only one that brings its own tokenizer base.
The terms are in x-lang's
[lang contract](https://github.com/jonruttan/x-lang/blob/main/docs/lang-contract.md).

## Status

**80 of 82 specs green** against x-lang **v0.9.0**.

That row is a *pairing* — what this bundle was last built and tested against —
but the floor beneath it is a hard requirement, unusually for this bundle:
x-lang v0.7.1 is the first release pinning an x-engine-c in which an isolated
tokenizer base works at all
([#528](https://github.com/jonruttan/x-lang/issues/528)). On anything earlier
this bundle is not merely failing, it is dead at load. `lang.xon` carries that
reasoning beside the row.

Last of the five 2024-era langs to come back, the largest, and the only
one that is not a Lisp. It is also the only one that was blocked on an engine
bug rather than on drift — see below.

The 2 that do not pass are the single- and double-quoted string readers: `''`
tokenizes correctly and `'a'` loses its accumulator, so the closing quote sees
an empty one. That is in how the tokenizer drives a state that scores nothing
on entry, and it wants someone reading the C token loop rather than more
guessing from outside.

## Install

Nothing cloned, from any directory:

```bash
x --install-lang https://github.com/jonruttan/x-ash/releases/latest/download/lang.pin.xon
x -l ash
```

x fetches the published pin, then the tarball it names, verifies the digest,
and installs to `<share>/langs/ash` — where `x -l` looks. A failed upgrade
leaves the working install untouched.

From a clone, if you have one:

```bash
make install                      # into the x on your PATH
PREFIX=$HOME/.local make install  # or a particular prefix
```

`make uninstall` removes it either way. An installed x searches
`<share>/langs/*/lang.xon`, so a lang is installed when its files are there —
no registry, no database.

**One trap, and it is the one you will hit.** `x` decides where to look for
langs from the directory you run it *in*. Inside an **x-lang checkout** it
searches `deps/langs/` and an installed lang is invisible, however correctly it
was installed:

```
$ cd path/to/x-lang && x -l ash
Error: no library, app or lang named 'ash'
  searched lib/ash.x, apps/ash/run.x
      and deps/langs/*/lang.xon
```

Run it from anywhere else, or name the bundles explicitly — `X_LANG_DIR` wins
in both modes:

```bash
X_LANG_DIR=$HOME/.local/share/x/langs/ x -l ash   # the installed one
X_LANG_DIR=/path/to/x-ash/.. x -l ash             # a checkout, uninstalled
```


**This bundle needs radon**, and `lang.xon` says so as a requirement rather
than a preference: ash forks, execs, dup2s and opens files, and Sys's process
and file doors are radon opt-ins. A lighter dialect would mean an unbound
symbol at the first pipeline instead of a legible refusal at acquisition.

## Pin it instead, for a project

An install is unversioned and machine-wide. When it matters *which* version a
project builds against, pin it: `Pin bundle` fetches the release tarball and
verifies it against a digest before unpacking. In the project's
`lang.pin.xon`:

```x
(lang "ash")
(release "v0.1.2")
(bundle "sha256:…" "https://github.com/jonruttan/x-ash/releases/download/v0.1.2/x-ash-v0.1.2.tar.gz")
(source "https://github.com/jonruttan/x-ash.git")
```

Each release publishes its own digest, and the release notes carry this block
ready to paste. Then:

```x-repl
> (import x/tool/pin)
> (Pin bundle "deps/langs")
"deps/langs/ash-v0.1.2"
```

`deps/langs/` is where `x -l` looks in a checkout. `X_LANG_DIR` overrides it.

**Which to use.** Install when you just want `x -l ash` to work. Pin when a
build depends on it — the digest is what makes the version reproducible, and
an install has none.

## Running it

```bash
x -l ash                # interactive
x -l ash -f script.sh   # batch
```

x-lang boots the dialect `lang.xon` declares, arms this bundle's module root,
and loads `run.x` on top — which is why nothing here needs to know a path.

## Development

Run the specs against any x-lang checkout or install:

```bash
X=/path/to/x-lang/x.sh make test    # the suite -- every failure is loud
X=/path/to/x-lang/x.sh make check   # the suite against the contract, which CI gates on
make bundle                         # roll a release tarball and print its pin
```

**Pass `X` explicitly.** Without it the suite takes the `x` on your PATH, and a
stale install reports failures the platform has already fixed — or, worse here,
a locally built `x-bin` that predates the engine the release pins. `x.sh
--engine-path` prefers the local build, and that is how this bundle once
reported 80 of 82 red on a platform where it passes.

**Do not `make install` into an x-lang checkout.** The Makefile asks
`$(X) --share-dir` where to put the bundle, and a checkout answers with its own
root — so the files land in `<checkout>/langs/NAME`, which is not one of the
three paths `-l` searches there. It reports success and the lang stays
invisible. Install into a real `<share>` tree, or use `X_LANG_DIR`.


The two failures are recorded by name in
[`tests/contract/known-failures.txt`](tests/contract/known-failures.txt), and
`make check` gates on that list rather than on a count — red when a new failure
appears *and* red when a recorded one starts passing. Documented debt can ship;
a regression cannot, and a fixed test cannot stay quietly excused.

The release tarball is byte-reproducible: it is built from the tag with
`git archive` and a timestamp-free gzip, so two people rolling one tag get one
digest. Pushing a `v*` tag runs the suite and, only if it is green, publishes
the tarball, its `.sha256` and `lang.pin.xon` as a GitHub release. CI runs the
declared release *and* x-lang `main`, so a platform that moves underneath this
bundle shows up as a red build rather than a surprise later.

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

## Background

The language here is POSIX's Shell Command Language: the Bourne shell's syntax
— V7 Unix, 1979 — as the standard later pinned it down. It is an odd and
underrated language: words rather than values, expansion rather than
evaluation, and a grammar in which `;` and newline are the sequencing
operators, which is exactly why this bundle needs its own tokenizer base.

It shares its name with the small-shell lineage begun by Kenneth Almquist's
`ash` (1989), which lives on as Debian's `dash` and BusyBox's `sh` — shells
that implement the standard and stop, which is this bundle's ambition too.

- [Shell Command Language](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html) — POSIX.1-2017, the language being implemented
- [Ash variants](https://www.in-ulm.de/~mascheck/various/ash/) — Sven Mascheck's history of the lineage
- [dash](http://gondor.apana.org.au/~herbert/dash/) — the lineage's current mainline

## Licence

MIT No Attribution (MIT-0). See [LICENSE](LICENSE).
