## sh-eval `.` looks for a bare name in PATH

A `.` operand holding no `/` is looked for in the directories of PATH, as
POSIX has it, and need not be executable: the first directory holding a
readable regular file of that name gives the file.  The working directory is
searched only when PATH names it, an empty entry among them.  An operand
holding a `/` is that path, never searched.

Expectations match `/bin/sh` and `dash` where they agree.  They part on three
corners.  bash looks in the working directory after PATH, and dash does not;
ash follows dash and POSIX, which names PATH alone.  At an unreadable file,
dash stops, and bash goes on to the next directory; ash follows bash, as POSIX
asks for a readable file.  A name found nowhere ends the subshell with 2 in
dash and 1 in bash; ash answers dash's 2, as it does for its other errors.
The fourth, fifth and last cases are pins that hold on main too.

### a name is found in a directory of PATH

```sh
(do (sh-eval "( d=$(mktemp -d); printf 'echo via-path\\n' > \"$d/f.sh\"; PATH=$d:$PATH; . f.sh; rm -rf \"$d\" )") ())
```
---
    via-path

### the first directory holding it gives the file

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir \"$d/a\" \"$d/b\"; printf 'echo first\\n' > \"$d/a/f.sh\"; printf 'echo second\\n' > \"$d/b/f.sh\"; PATH=$d/a:$d/b:$PATH; . f.sh; rm -rf \"$d\" )") ())
```
---
    first

### the working directory is not searched when PATH does not name it

```sh
(do (sh-eval "( d=$(mktemp -d); cd \"$d\"; printf 'echo in-cwd\\n' > c.sh; PATH=/usr/bin:/bin; ( . c.sh ) 2>/dev/null || echo not-searched; cd /; rm -rf \"$d\" )") ())
```
---
    not-searched

### an empty entry in PATH names the working directory

```sh
(do (sh-eval "( d=$(mktemp -d); cd \"$d\"; printf 'echo empty-entry\\n' > e.sh; PATH=:/usr/bin:/bin; . e.sh; cd /; rm -rf \"$d\" )") ())
```
---
    empty-entry

### a name holding a slash is not searched

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir \"$d/sub\"; printf 'echo wrong\\n' > \"$d/sub/s.sh\"; cd \"$d\"; PATH=$d/sub:/usr/bin:/bin; ( . ./s.sh ) 2>/dev/null || echo slash-not-searched; cd /; rm -rf \"$d\" )") ())
```
---
    slash-not-searched

### a directory of that name is passed by

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir -p \"$d/a/f.sh\" \"$d/b\"; printf 'echo past-dir\\n' > \"$d/b/f.sh\"; PATH=$d/a:$d/b:$PATH; . f.sh; rm -rf \"$d\" )") ())
```
---
    past-dir

### an unreadable file is passed by

```sh
(do (sh-eval "( d=$(mktemp -d); mkdir \"$d/a\" \"$d/b\"; printf 'echo a\\n' > \"$d/a/u.sh\"; chmod 000 \"$d/a/u.sh\"; printf 'echo b\\n' > \"$d/b/u.sh\"; PATH=$d/a:$d/b:$PATH; . u.sh; chmod 644 \"$d/a/u.sh\"; rm -rf \"$d\" )") ())
```
---
    b

### a name found nowhere is an error of the `.`

```sh
(do (sh-eval "( PATH=/usr/bin:/bin; ( . nosuchdotfile.sh ) 2>/dev/null; echo \"s=$?\" )") ())
```
---
    s=2
