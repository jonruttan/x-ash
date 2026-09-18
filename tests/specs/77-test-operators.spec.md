## sh-eval test's other operators

Besides `-e -f -d -s`, `test` answers:

  - `-L` and `-h`, a symbolic link, asked of the path itself; every other file
    test follows a link, so `-e` on a dangling one is false
  - `-p` a FIFO, `-S` a socket, `-b` a block device, `-c` a character device
  - `-u`, `-g` and `-k`, the setuid, setgid and sticky bits
  - `-t FD`, whether a descriptor is a terminal
  - `f1 -nt f2` and `f1 -ot f2`, by modification time
  - `s1 < s2` and `s1 > s2`, by byte

`-r`, `-w` and `-x` are not among them: they ask access(2), which answers for
the process as well as the file, and the platform has no door to it yet.

Expectations match `/bin/sh` and `dash` but for two, where they disagree with
each other and this follows bash:

  - a file that is missing is older than one that is there, so
    `here -nt missing` is true -- the reading POSIX.1-2024 gives; dash
    answers false when either is missing
  - `-t` of a word that is no number is false; dash calls it an illegal
    number and answers 2

### a symbolic link, dangling or not

```sh
(do (sh-eval "( d=$(mktemp -d); cd \"$d\"; : > t; ln -s t l; ln -s nowhere dangling; [ -L l ] && [ -h l ] && [ ! -L t ] && [ -L dangling ] && [ ! -e dangling ] && echo links; cd /; rm -rf \"$d\" )") ())
```
---
    links

### a FIFO

```sh
(do (sh-eval "( d=$(mktemp -d); cd \"$d\"; mkfifo p; [ -p p ] && [ ! -p \"$d\" ] && echo fifo; cd /; rm -rf \"$d\" )") ())
```
---
    fifo

### devices

```sh
(do (sh-eval "( [ -c /dev/null ] && [ ! -b /dev/null ] && [ ! -c /tmp ] && echo devs )") ())
```
---
    devs

### a descriptor that is no terminal is false, not an error

```sh
(do (sh-eval "( [ -t 99 ]; echo \"s=$?\" )") ())
```
---
    s=1

### so is a word that is no descriptor

```sh
(do (sh-eval "( [ -t x ]; echo \"s=$?\" )") ())
```
---
    s=1

### the sticky bit

```sh
(do (sh-eval "( d=$(mktemp -d); chmod +t \"$d\"; [ -k \"$d\" ] && echo sticky; rm -rf \"$d\" )") ())
```
---
    sticky

### a plain file has none of the three, each answering false

```sh
(do (sh-eval "( f=$(mktemp); [ -u \"$f\" ]; u=$?; [ -g \"$f\" ]; g=$?; [ -k \"$f\" ]; k=$?; rm -f \"$f\"; echo \"$u$g$k\" )") ())
```
---
    111

### newer and older

```sh
(do (sh-eval "( d=$(mktemp -d); cd \"$d\"; touch -t 202001010000 old; touch new; [ new -nt old ] && [ old -ot new ] && [ ! old -nt new ] && echo times; cd /; rm -rf \"$d\" )") ())
```
---
    times

### a missing file is older than any

```sh
(do (sh-eval "( d=$(mktemp -d); cd \"$d\"; : > here; [ here -nt missing ] && [ missing -ot here ] && [ ! missing -nt here ] && echo missing; cd /; rm -rf \"$d\" )") ())
```
---
    missing

### strings by byte

```sh
(do (sh-eval "( [ a \\< b ] && [ b \\> a ] && [ ! b \\< a ] && [ A \\< a ] && echo strings )") ())
```
---
    strings

### a prefix sorts first

```sh
(do (sh-eval "( [ abc \\< abd ] && [ ab \\< abc ] && echo prefix )") ())
```
---
    prefix
