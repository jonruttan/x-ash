## sh-eval tilde expansion

`~` stands for HOME at the start of a word, and -- in an assignment word only
-- after its `=` and after any `:` beyond that, which is what makes
`PATH=~/bin:~/lib` work.  Anywhere else it is an ordinary character.  HOME is
set in each case rather than inherited, so the expectation is a fact of the
spec and not of the machine; each was taken from `/bin/sh` first.  The
assignment cases read their variable back QUOTED for the same reason: spec
files share a process under batching, and the IFS file leaves IFS at `:`, so
an unquoted read would be a test of field splitting wearing a tilde costume.

`~user` is not expanded: it wants the password database and the platform has
no door to it, so it is left as written -- which is what a shell does for a
user that does not exist.

### a bare tilde is HOME

```sh
(do (sh-eval "HOME=/h; echo ~") ())
```
---
    /h

### and it keeps what follows the slash

```sh
(do (sh-eval "HOME=/h; echo ~/x") ())
```
---
    /h/x

### the prefix ends at a colon too

```sh
(do (sh-eval "HOME=/h; echo ~:x") ())
```
---
    /h:x

### each word expands its own

```sh
(do (sh-eval "HOME=/h; echo ~ ~") ())
```
---
    /h /h

### double quotes suppress it

```sh
(do (sh-eval "HOME=/h; echo \"~\"") ())
```
---
    ~

### single quotes suppress it

```sh
(do (sh-eval "HOME=/h; echo '~'") ())
```
---
    ~

### a backslash suppresses it

```sh
(do (sh-eval "HOME=/h; echo \\~") ())
```
---
    ~

### a tilde inside a word is ordinary

```sh
(do (sh-eval "HOME=/h; echo a~b") ())
```
---
    a~b

### a tilde at the END of a word is ordinary

```sh
(do (sh-eval "HOME=/h; echo x~") ())
```
---
    x~

### a name after it is left as written

```sh
(do (sh-eval "HOME=/h; echo ~nosuch") ())
```
---
    ~nosuch

### an assignment expands after its =

```sh
(do (sh-eval "HOME=/h; V=~/x; echo \"$V\"") ())
```
---
    /h/x

### and after a colon beyond it

```sh
(do (sh-eval "HOME=/h; V=a:~/x; echo \"$V\"") ())
```
---
    a:/h/x

### but only after the FIRST =

```sh
(do (sh-eval "HOME=/h; V=a=~/x; echo \"$V\"") ())
```
---
    a=~/x

### an argument that looks like an assignment is not one

```sh
(do (sh-eval "HOME=/h; echo a=~/x") ())
```
---
    a=~/x
