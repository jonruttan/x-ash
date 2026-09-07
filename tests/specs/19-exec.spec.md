## sh-eval exec

Two commands wearing one name, told apart by whether a command follows:

    exec CMD [args]   replace this shell with CMD; nothing after it runs
    exec [redirs]     apply the redirections TO THIS SHELL and carry on

The second is the one with teeth: `exec > log` sends the rest of the script to
log, so exec is the one builtin whose redirections are NOT put back when it
returns.  The cases below run it in a subshell, because a spec that redirected
the harness's own output would take the suite with it.

Each expectation was taken from `/bin/sh` first.

### it replaces the shell, so nothing after it runs

```sh
(do (sh-eval "( exec echo replaced; echo notreached )") ())
```
---
    replaced

### an absolute path works the same

```sh
(do (sh-eval "( exec /bin/echo hi )") ())
```
---
    hi

### with no command and no redirection it does nothing and succeeds

```sh
(do (sh-eval "exec; echo bare-ok") ())
```
---
    bare-ok

### a redirection with no command OUTLIVES the exec

```sh
(do (sh-eval "v=$( ( exec > /dev/null; echo hidden ); echo shown ); echo \"[$v]\"") ())
```
---
    [shown]

### and so does one on stderr

```sh
(do (sh-eval "w=$( ( exec 2>/dev/null; nosuchcmd_zz; echo after ) ); echo \"[$w]\"") ())
```
---
    [after]

### opening a spare descriptor succeeds

```sh
(do (sh-eval "( exec 3>/dev/null; echo fd3-ok )") ())
```
---
    fd3-ok

### a command that cannot be run answers 127

```sh
(do (sh-eval "( exec nosuchcmd_zz ); echo $?") ())
```
---
    127

### it replaces the shell from inside a function too

```sh
(do (sh-eval "( f() { exec echo fn; }; f; echo notreached )") ())
```
---
    fn
