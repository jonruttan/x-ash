## sh-eval running an assignment

An assignment word is split at its first `=` by one scan on the integer
doors, the same scan for the name as for the value.  A name the shell's table
holds is not exported -- every way into the environment or the export marks
takes a name out of the table -- so it is set in place without asking the
environment.  An exported name, a name marked for export, one assigned under
`set -a`, and a prefix assignment to a command still reach the environment.

Expectations match `/bin/sh` and `dash`.  The first three cases are pins that
hold on main too.  The cost is compared rather than counted, as spec 36
compares its tests.

### names and values

```sh
(do (sh-eval "( a=b=c; _x1=5; echo \"$a $_x1\"; X=1 : ; echo \"[$X]\" ) | tr '\\n' ','; echo") ())
```
---
    b=c 5,[1],

### where each assignment lands

```sh
(do (sh-eval "( export E=1; E=2; /usr/bin/env | grep '^E='; F=3; /usr/bin/env | grep -c '^F='; x=1; export x; x=2; /usr/bin/env | grep '^x='; export y; y=3; /usr/bin/env | grep '^y='; set -a; G=4; set +a; /usr/bin/env | grep '^G='; H=5 /usr/bin/env | grep '^H='; echo \"H=[$H]\" ) | tr '\\n' ','; echo") ())
```
---
    E=2,0,x=2,y=3,G=4,H=5,H=[],

### a read-only name refuses an assignment and an unset

```sh
(do (sh-eval "( ( readonly r=1; r=2; echo not-reached ) 2>/dev/null || echo refused; ( r=1; readonly r; unset r ) 2>/dev/null || echo kept ) | tr '\\n' ','; echo") ())
```
---
    refused,kept,

### splitting `i=6` five times costs less than twelve comparisons

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) ((fn (self i) (if (fx<? i 5) (do (%sh-assignment-name "i=6") (%sh-assignment-value "i=6") (self (fx+ i 1))) ())) 0)))
     (cost (fn (_) ((fn (self i) (if (fx<? i 12) (do (>= i 3) (self (fx+ i 1))) ())) 0)))))
```
---
    #t
