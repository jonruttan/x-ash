## sh-eval command substitution

### $( ) answers what the command printed

```sh
(do (sh-eval "echo [$(echo hi)]") ())
```
---
    [hi]

### an assignment takes a substitution

```sh
(do (sh-eval "X=$(echo val); echo $X") ())
```
---
    val

### a substitution joins the word around it

```sh
(do (sh-eval "echo pre$(echo MID)post") ())
```
---
    preMIDpost

### substitutions nest

```sh
(do (sh-eval "echo $(echo a$(echo b)c)") ())
```
---
    abc

### a substitution inside double quotes expands

```sh
(do (sh-eval "echo \"got $(echo x) here\"") ())
```
---
    got x here

### single quotes suppress a substitution

```sh
(do (sh-eval "echo '$(echo no)'") ())
```
---
    $(echo no)

### a quoted paren inside does not close the substitution

```sh
(do (sh-eval "echo $(echo ')')") ())
```
---
    )

### trailing newlines are stripped

```sh
(do (sh-eval "echo [$(echo x)]") ())
```
---
    [x]

### a substitution producing nothing is empty

```sh
(do (sh-eval "echo [$(true)]") ())
```
---
    []

### the backtick form works too

```sh
(do (sh-eval "echo [`echo old`]") ())
```
---
    [old]

### an unclosed substitution is literal

```sh
(do (sh-eval "echo $(echo") ())
```
---
    $(echo

## sh-eval tokenizing substitutions

### $( ) is one word, parens and all

```sh
(write (sh-tokenize "echo $(pwd)"))
```
---
    ((tok-word "echo") (tok-word "$(pwd)"))

### a nested substitution stays one word

```sh
(write (sh-tokenize "echo $(echo $(echo deep))"))
```
---
    ((tok-word "echo") (tok-word "$(echo $(echo deep))"))

### a substitution joins the text around it

```sh
(write (sh-tokenize "a$(pwd)b"))
```
---
    ((tok-word "a$(pwd)b"))
