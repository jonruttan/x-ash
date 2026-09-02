## ash-complete? single lines

### a plain command is complete

```sh
(write (%ash-complete? "echo hi"))
```
---
    #t

### an empty line is complete

```sh
(write (%ash-complete? ""))
```
---
    #t

### a one-line for loop is complete

```sh
(write (%ash-complete? "for f in a b; do echo $f; done"))
```
---
    #t

## ash-complete? unfinished entries

### a for without its done is not complete

```sh
(write (%ash-complete? "for f in a b"))
```
---
    ()

### a while without its done is not complete

```sh
(write (%ash-complete? "while true"))
```
---
    ()

### an if without its fi is not complete

```sh
(write (%ash-complete? "if test a = a"))
```
---
    ()

### a case without its esac is not complete

```sh
(write (%ash-complete? "case $x in"))
```
---
    ()

### an unclosed single quote is not complete

```sh
(write (%ash-complete? "echo 'abc"))
```
---
    ()

### an unclosed double quote is not complete

```sh
(write (%ash-complete? "echo \"abc"))
```
---
    ()

### a trailing pipe is not complete

```sh
(write (%ash-complete? "echo hi |"))
```
---
    ()

### a trailing && is not complete

```sh
(write (%ash-complete? "true &&"))
```
---
    ()

### a trailing backslash is not complete

```sh
(write (%ash-complete? "echo a \\"))
```
---
    ()

### an unclosed subshell is not complete

```sh
(write (%ash-complete? "( echo hi"))
```
---
    ()

## ash-complete? things that only look unfinished

### a lone background ampersand is complete

```sh
(write (%ash-complete? "sleep 1 &"))
```
---
    #t

### a keyword inside quotes does not open a block

```sh
(write (%ash-complete? "echo 'if'"))
```
---
    #t

### a closed multi-line entry is complete

```sh
(do (def nl (make-string 1 (convert 10 %char))) (write (%ash-complete? (string-append (string-append "for f in a b" nl) "do echo $f; done"))))
```
---
    #t
