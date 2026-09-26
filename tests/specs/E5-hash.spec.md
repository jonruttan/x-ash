## sh-eval hash

`hash NAME...` looks each name up as a command and remembers the file where
one is found on PATH; `hash` alone writes what it remembers, one path a line;
`hash -r` forgets it all, and so does assigning PATH.  A function or a builtin
is found and not remembered, a reserved word or an alias is not a command, and
a name found nowhere is reported and answers 1 while the names after it are
still taken.  This shell looks along PATH for every command all the same, so
what is remembered is only what `hash` reports.

Expectations match `/bin/sh` (bash 3.2) and `dash`, which agree on every case
here.  The listing is dash's, a path a line; bash writes a table of hits
before them.  Paths are compared with what `command -v` answers, so the cases
hold wherever the utilities are installed.

Each case runs in a subshell, so what it remembers goes with it.  A case that
holds on main as well is stated as a pin.

### hash remembers where a command is and writes it

```sh
(do (sh-eval "(hash ls cat; [ \"$(hash)\" = \"$(command -v ls; command -v cat)\" ] && echo listed)") ())
```
---
    listed

### a name found nowhere answers 1, and the names after it are still taken

```sh
(do (sh-eval "({ hash zq9nosuch cat 2>/dev/null; echo \"st=$?\"; hash | wc -l | tr -d ' '; } | tr '\\n' ,; echo)") ())
```
---
    st=1,1,

### hash -r forgets what was remembered

```sh
(do (sh-eval "(hash ls cat; hash -r; hash cat; hash | wc -l | tr -d ' ')") ())
```
---
    1

### assigning PATH forgets it too

```sh
(do (sh-eval "(hash ls cat; PATH=$PATH; hash sh; hash | wc -l | tr -d ' ')") ())
```
---
    1

### a builtin, a function and a path are found and not remembered

```sh
(do (sh-eval "(f() { :; }; { hash echo f /zq9/nosuch; echo \"st=$?\"; hash | wc -l | tr -d ' '; } | tr '\\n' ,; echo)") ())
```
---
    st=0,0,

### pin: a reserved word and an alias are not commands

```sh
(do (sh-eval "(alias zq9=echo; hash if zq9 2>/dev/null; echo \"st=$?\")") ())
```
---
    st=1
