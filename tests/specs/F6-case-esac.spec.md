## sh-eval a case ends at its esac

A clause that does not match is skipped to its `;;`, and the next clause is
read after it; when the last clause omits its `;;`, the skip reaches the
`esac`, and the case is over there.  What follows the `esac` in the same
command is the case's redirection, not a clause.

Expectations match `dash` and `/bin/sh`.  The third case holds on main too.

### a last clause without `;;`, skipped, before a redirection

```sh
(do (sh-eval "( case x in a) echo a; esac >/dev/null; echo after $?; case x in a) :;; b) :; esac 2>/dev/null; echo after $? ) 2>&1 | tr '\\n' ','; echo") ())
```
---
    after 0,after 0,

### a skipped clause holding a case of its own

```sh
(do (sh-eval "( case x in a) case y in y) :;; esac; esac 2>&1; echo after $? ) 2>&1 | tr '\\n' ','; echo") ())
```
---
    after 0,

### a last clause with its `;;`, and one that matches

```sh
(do (sh-eval "( case z in a) echo a;; esac >/dev/null && echo and; case b in a) :;; b) echo b; esac; echo after $? ) 2>&1 | tr '\\n' ','; echo") ())
```
---
    and,b,after 0,
