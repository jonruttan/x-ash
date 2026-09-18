## sh-eval pipefail, and `o` inside a cluster

A pipeline's status is its last stage's.  Under `set -o pipefail` it is the
status of the last stage that failed, or 0 when none did, so a failure early
in a pipeline is not lost behind a stage that succeeded after it.

An `o` among a cluster's letters takes its option's name from the words after
the cluster, in turn: `set -euo pipefail` is `set -e -u -o pipefail`, and
`set -oe pipefail` reads the same.  pipefail has no letter of its own, so it
is not in `$-`.

POSIX.1-2024 specifies pipefail; the `dash` on this system predates it, so
the expectations match `/bin/sh`.

### without pipefail the last stage answers

```sh
(do (sh-eval "( false | true; echo \"s=$?\" )") ())
```
---
    s=0

### with it a failed stage does

```sh
(do (sh-eval "( set -o pipefail; false | true; echo \"s=$?\" )") ())
```
---
    s=1

### and of several, the last to fail

```sh
(do (sh-eval "( set -o pipefail; (exit 3) | (exit 5) | true; echo \"s=$?\" )") ())
```
---
    s=5

### wherever it stands

```sh
(do (sh-eval "( set -o pipefail; false | true | (exit 4) | true; echo \"s=$?\" )") ())
```
---
    s=4

### a pipeline with no failure answers 0

```sh
(do (sh-eval "( set -o pipefail; true | true; echo \"s=$?\" )") ())
```
---
    s=0

### +o turns it off

```sh
(do (sh-eval "( set -o pipefail; set +o pipefail; false | true; echo \"s=$?\" )") ())
```
---
    s=0

### the status reaches a command substitution's

```sh
(do (sh-eval "( set -o pipefail; x=$(false | true); echo \"s=$?\" )") ())
```
---
    s=1

### negation reads it

```sh
(do (sh-eval "( set -o pipefail; ! false | true; echo \"s=$?\" )") ())
```
---
    s=0

### errexit ends the shell at a pipeline that fails under it

```sh
(do (sh-eval "( set -eo pipefail; false | true; echo reached ); echo \"sub=$?\"") ())
```
---
    sub=1

### and without it lets an early failure pass

```sh
(do (sh-eval "( set -e; false | true; echo reached )") ())
```
---
    reached

### set -euo pipefail turns on all three

```sh
(do (sh-eval "( set -euo pipefail; false | true; echo reached ); echo \"sub=$?\"") ())
```
---
    sub=1

### nounset among them

```sh
(do (sh-eval "( set -euo pipefail; echo \"$undefined_name\"; echo reached ) 2>/dev/null; [ $? -ne 0 ] && echo stopped") ())
```
---
    stopped

### an o ahead of another letter still takes the word after the cluster

```sh
(do (sh-eval "( set -oe pipefail; false | true; echo reached ); echo \"sub=$?\"") ())
```
---
    sub=1

### pipefail is not a letter of $-

```sh
(do (sh-eval "( a=$-; set -o pipefail; [ \"$a\" = \"$-\" ] && echo same )") ())
```
---
    same
