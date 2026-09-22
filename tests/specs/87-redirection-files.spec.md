## sh-eval the files a redirection opens

`>` and `>>` create a file with permission 0666 less the umask, as `touch`
does, and leave the mode of a file that is already there alone.  `<>` opens
its file for reading and writing, and creates it when it is not there.

Expectations match `/bin/sh` and `dash`.

### > creates a file with the mode touch gives

```sh
(do (sh-eval "( d=$(mktemp -d); : > \"$d/a\"; touch \"$d/b\"; [ \"$(ls -l \"$d/a\" | cut -c1-10)\" = \"$(ls -l \"$d/b\" | cut -c1-10)\" ] && echo same-as-touch; rm -rf \"$d\" )") ())
```
---
    same-as-touch

### and so does >>

```sh
(do (sh-eval "( d=$(mktemp -d); echo x >> \"$d/a\"; touch \"$d/b\"; [ \"$(ls -l \"$d/a\" | cut -c1-10)\" = \"$(ls -l \"$d/b\" | cut -c1-10)\" ] && echo append-same; rm -rf \"$d\" )") ())
```
---
    append-same

### > leaves an existing file's mode alone

```sh
(do (sh-eval "( f=$(mktemp); chmod 600 \"$f\"; echo x > \"$f\"; ls -l \"$f\" | cut -c1-10; rm -f \"$f\" )") ())
```
---
    -rw-------

### and so does >>

```sh
(do (sh-eval "( f=$(mktemp); chmod 600 \"$f\"; echo x >> \"$f\"; ls -l \"$f\" | cut -c1-10; rm -f \"$f\" )") ())
```
---
    -rw-------

### whatever the mode is

```sh
(do (sh-eval "( f=$(mktemp); chmod 640 \"$f\"; echo y > \"$f\"; echo z >> \"$f\"; ls -l \"$f\" | cut -c1-10; rm -f \"$f\" )") ())
```
---
    -rw-r-----

### <> writes as well as reads

```sh
(do (sh-eval "( f=$(mktemp); echo old > \"$f\"; echo new 1<>\"$f\"; cat \"$f\"; rm -f \"$f\" )") ())
```
---
    new

### <> creates a file that is not there

```sh
(do (sh-eval "( d=$(mktemp -d); : <> \"$d/n\"; [ -f \"$d/n\" ] && echo created; rm -rf \"$d\" )") ())
```
---
    created

### exec opens a descriptor for both

```sh
(do (sh-eval "( f=$(mktemp); exec 3<>\"$f\"; echo hi >&3; exec 3>&-; cat \"$f\"; rm -f \"$f\" )") ())
```
---
    hi
