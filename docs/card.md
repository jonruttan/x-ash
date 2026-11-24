# x-ash card

## Run

```sh
x -l ash
x -l ash -- SCRIPT [ARG...]
x -l ash -- -c 'echo hello' -> hello
x -l ash -- -c 'echo $0 $1' name arg -> name arg
echo 'echo from stdin' | x -l ash -> from stdin
echo 'echo $1' | x -l ash -- -s arg -> arg
x -l ash -- -c 'exit 3'; echo $? -> 3
x -l ash -- -c 'false; echo next' -> next
x -l ash -- -e -c 'false; echo next'; echo $? -> 1
```

| Line                           | Runs                                   |
|--------------------------------|----------------------------------------|
| `x -l ash`                     | the prompt, or a script on stdin       |
| `x -l ash -- SCRIPT ARG...`    | a file; `$0` is SCRIPT, `$1` the first ARG |
| `x -l ash -- -c 'TEXT' NAME ARG...` | TEXT; `$0` is NAME                |
| `x -l ash -- -s ARG...`        | standard input, with arguments         |
| `x -l ash -- -e SCRIPT`        | with an option `set` takes             |
| `--`                           | ends x's own options; the shell's follow |

## Words

| Written        | Is                                                      |
|----------------|---------------------------------------------------------|
| `'TEXT'`       | TEXT as it stands                                       |
| `"TEXT"`       | TEXT with `$`, `` ` `` and `\` still read; one word     |
| `\C`           | the character C itself                                  |
| `$'a\tb'`      | TEXT with `\n \t \\ \xHH \ddd` escapes read             |
| `a"b"'c'`      | one word: quoting covers a part of a word               |
| `# TEXT`       | a comment, to the end of the line                       |
| `~` `~/bin`    | the home directory                                      |

```ash
name=world
echo 'single: $name'              # -> single: $name
echo "double: $name"              # -> double: world
echo a\ b     c                   # -> a b c
echo pre"mid"'post'               # -> premidpost
echo $'\x41\102'                  # -> AB
echo "a  b" 'c  d'                # -> a  b c  d
```

## Parameters

| Name            | Holds                                                |
|-----------------|------------------------------------------------------|
| `NAME=VALUE`    | sets NAME; no blanks around `=`                      |
| `$NAME` `${NAME}` | its value; nothing when it is unset                |
| `$1` ... `$9`, `${10}` | the arguments, by position                    |
| `$#`            | how many arguments there are                         |
| `$@` `$*`       | all of them; `"$@"` is each as its own word          |
| `$?`            | the status of the last command                       |
| `$$`            | the shell's process id                               |
| `$0`            | the script's name                                    |
| `NAME=VALUE CMD` | NAME is set for CMD alone                           |

```ash
set -- one two three
echo $# $1 $3                     # -> 3 one three
echo "$@"                         # -> one two three
shift
echo $1 $#                        # -> two 2
false
echo $?                           # -> 1
greeting=hi sh -c 'echo $greeting'  # -> hi
echo "[$greeting]"                # -> []
```

### Expansion

| Form            | Gives                                                 |
|-----------------|-------------------------------------------------------|
| `${X:-WORD}`    | WORD when X is unset or empty                         |
| `${X:=WORD}`    | the same, and X is set to WORD                        |
| `${X:?WORD}`    | an error saying WORD when X is unset or empty         |
| `${X:+WORD}`    | WORD when X has a value, else nothing                 |
| `${X-WORD}`     | without the colon: an empty X counts as set           |
| `${#X}`         | the length of X                                       |
| `${X#PAT}`      | X less the shortest start that fits PAT               |
| `${X##PAT}`     | less the longest start                                |
| `${X%PAT}`      | less the shortest end                                 |
| `${X%%PAT}`     | less the longest end                                  |

```ash
unset u
e=
p=/usr/lib/libx.so.1
echo ${u:-default}                # -> default
echo "[${e-set}]" "[${e:-empty}]" # -> [] [empty]
echo ${u:=assigned} $u            # -> assigned assigned
echo ${p:+has a value}            # -> has a value
echo ${#p}                        # -> 18
echo ${p##*/}                     # -> libx.so.1
echo ${p%/*}                      # -> /usr/lib
echo ${p%%.*}                     # -> /usr/lib/libx
echo ${p#/*/}                     # -> lib/libx.so.1
```

## Substitution

| Form           | Gives                                                  |
|----------------|--------------------------------------------------------|
| `$(CMD)`       | what CMD prints, less its trailing newlines            |
| `` `CMD` ``    | the same, the older spelling                           |
| `$((EXPR))`    | the integer EXPR works out to                          |

| In `$(( ))`             | Is                                            |
|-------------------------|-----------------------------------------------|
| `12` `010` `0x10`       | decimal, octal, hexadecimal                   |
| `+ - * / %`             | arithmetic; division drops the fraction       |
| `< <= > >= == !=`       | comparison: 1 or 0                            |
| `& \| ^ ~ << >>`         | bitwise                                       |
| `&& \|\| !`              | logical; only the side taken is worked out    |
| `C ? A : B`             | A when C is not zero, else B                  |
| `NAME`                  | its value; 0 when unset or not a number       |

```ash
n=$(echo 4)
echo "`echo back` $(echo nested $(echo deep))"    # -> back nested deep
echo $((n * 3 + 1))               # -> 13
echo $((7 / 2)) $((-7 / 2)) $((7 % 3))    # -> 3 -3 1
echo $((0x10 + 010))              # -> 24
echo $((n > 3 ? 1 : 0)) $((1 << 4)) $((6 & 3))    # -> 1 16 2
echo $((0 && 1 / 0))              # -> 0
i=0
i=$((i + 1))
echo $i                           # -> 1
```

## Splitting and matching

| Written          | Becomes                                              |
|------------------|------------------------------------------------------|
| `$X`             | a word for each field of X, split on `IFS`           |
| `"$X"`           | one word, as X stands                                |
| `$X`, X empty    | no word at all; `""` is one empty word               |
| `*`              | any run of characters in a name                      |
| `?`              | any one character                                    |
| `[abc]` `[a-z]` `[!abc]` | one character of these, or of none of these  |
| `'*'` `"*"` `\*` | a star                                               |
| a pattern that fits no name | itself, as written                        |
| a leading `.`    | fits only a pattern that starts with one             |

```ash
x="a b"
set -- $x
echo $#                           # -> 2
set -- "$x"
echo $#                           # -> 1
set -- $none
echo $#                           # -> 0
set -- ""
echo $#                           # -> 1
IFS=:
set -- $(echo a::b)
echo $#                           # -> 3
```

```ash
touch a.txt b.txt .hidden
echo *.txt                        # -> a.txt b.txt
echo *                            # -> a.txt b.txt
echo ?.txt [b]*                   # -> a.txt b.txt b.txt
echo "*.txt" \*                   # -> *.txt *
echo *.none                       # -> *.none
```

## Commands

| Form              | Runs                                                |
|-------------------|-----------------------------------------------------|
| `A; B`            | A, then B                                           |
| `A && B`          | B when A succeeded                                  |
| `A \|\| B`          | B when A failed                                     |
| `A \| B`           | both, A's output as B's input                       |
| `! A`             | A, its status turned over                           |
| `A &`             | A without waiting; `wait` waits for it              |
| `{ A; B; }`       | a group, in this shell                              |
| `( A; B )`        | a subshell: what it sets does not come back         |

```ash
true && echo yes                  # -> yes
false || echo no                  # -> no
! false && echo turned            # -> turned
echo b a | tr ' ' '\n' | sort | head -n 1   # -> a
{ echo one; echo two; } | wc -l | tr -d ' ' # -> 2
(exit 3)
echo $?                           # -> 3
v=out
(v=in)
echo $v                           # -> out
```

### Redirection

| Form        | Does                                                      |
|-------------|-----------------------------------------------------------|
| `< FILE`    | reads standard input from FILE                            |
| `> FILE`    | writes standard output to FILE, emptied first             |
| `>> FILE`   | adds to the end of FILE                                   |
| `>\| FILE`   | writes over FILE even under `set -C`                      |
| `<> FILE`   | opens FILE to read and write                              |
| `2> FILE`   | a number in front names the descriptor                    |
| `2>&1`      | descriptor 2 goes where 1 goes                            |
| `<<WORD`    | the lines up to WORD are standard input, expanded         |
| `<<'WORD'`  | the same, as they stand                                   |
| `<<-WORD`   | the same, leading tabs dropped                            |
| `exec > FILE` | redirects the shell itself                              |

```ash
echo first > log
echo second >> log
wc -l < log | tr -d ' '           # -> 2
cat nothere 2> /dev/null || echo quiet    # -> quiet
exec 3< log
read line <&3
echo $line                        # -> first
for w in a b; do echo $w; done > out
tail -n 1 out                     # -> b
cat <<EOF                         # -> sum: 3
sum: $((1 + 2))
EOF
cat <<'EOF'                       # -> raw: $((1 + 2))
raw: $((1 + 2))
EOF
```

## Control

| Form                                    | Runs                          |
|-----------------------------------------|-------------------------------|
| `if A; then B; elif C; then D; else E; fi` | by the status of A, then C |
| `while A; do B; done`                   | B while A succeeds            |
| `until A; do B; done`                   | B until A succeeds            |
| `for X in WORD...; do B; done`          | B with X as each word         |
| `case WORD in PAT\|PAT) B ;; esac`       | the first B whose PAT fits    |
| `break [N]` `continue [N]`              | leaves or restarts N loops    |

```ash
n=3
if [ $n -gt 5 ]; then
  echo big
elif [ $n -gt 2 ]; then
  echo middling                   # -> middling
else
  echo small
fi

while [ $n -gt 0 ]; do n=$((n - 1)); done
echo $n                           # -> 0
until [ $n -ge 2 ]; do n=$((n + 1)); done
echo $n                           # -> 2

for f in a b c; do
  [ $f = b ] && continue
  echo $f                         # -> a
done                              # -> c

case file.txt in
  *.c)        echo source ;;
  *.txt|*.md) echo text ;;        # -> text
  *)          echo other ;;
esac
```

## Functions

| Form                | Is                                                  |
|---------------------|-----------------------------------------------------|
| `NAME() { ...; }`   | a function; any compound command can be its body    |
| `$1` `$#` `$@`      | its own arguments during the call                   |
| `local X=V`         | X for this call, and for what it calls              |
| `return [N]`        | leaves it with status N                             |
| `command NAME`      | runs the builtin or the file, not the function      |

```ash
greet() {
  local who=${1:-you}
  echo "hello $who, $# given"
  return 4
}
who=outside
greet world                       # -> hello world, 1 given
echo $?                           # -> 4
greet                             # -> hello you, 0 given
echo $who                         # -> outside

echo() { command echo "mine: $*"; }
echo hi                           # -> mine: hi
```

## Builtins

| Builtin                    | Does                                         |
|----------------------------|----------------------------------------------|
| `echo [-n] WORD...`        | prints its words                             |
| `cd [-L\|-P] [DIR]` `pwd`   | the working directory; `cd -` goes back      |
| `read [-r] [-d C] NAME...` | a line into the names, the last takes the rest |
| `export NAME[=V]`          | NAME goes to the commands this shell runs    |
| `readonly NAME[=V]`        | NAME cannot be set again                     |
| `unset [-f\|-v] NAME`       | removes a variable or a function             |
| `set -- WORD...`           | replaces the arguments                       |
| `shift [N]`                | drops the first N arguments                  |
| `. FILE`                   | runs FILE in this shell                      |
| `eval WORD...`             | runs its words as a command                  |
| `exec CMD`                 | replaces the shell with CMD                  |
| `getopts SPEC NAME`        | the next option of the arguments into NAME   |
| `command -v NAME` `type NAME` | what NAME would run                       |
| `alias N=V` `unalias N`    | N as a command's name is read as V           |
| `trap ACTION EXIT`         | runs ACTION when the shell exits             |
| `wait [PID...]`            | waits for what `&` started                   |
| `exit [N]`                 | leaves the shell with status N               |
| `true` `false` `:`         | status 0, 1, 0                               |
| `hash [-r] [NAME...]`      | remembers where a command is                 |

```input
alpha beta gamma
```

```ash
trap 'echo bye' EXIT
read first rest
echo $rest                        # -> beta gamma
eval 'v=7'
echo $v                           # -> 7
command -v cd                     # -> cd

set -- -a -b val file
while getopts ab: opt; do
  echo "$opt=${OPTARG:-}"         # -> a=
done                              # -> b=val
shift $((OPTIND - 1))
echo $1                           # -> file
                                  # -> bye
```

### test

| Test                    | Holds when                                     |
|-------------------------|------------------------------------------------|
| `[ -n S ]` `[ -z S ]`   | S is not empty; is empty                       |
| `[ A = B ]` `[ A != B ]` | the strings are the same; differ              |
| `[ A -eq B ]`           | the integers are equal: also `-ne -lt -le -gt -ge` |
| `[ -e F ]`              | F is there: `-f` a file, `-d` a directory      |
| `[ -s F ]`              | F is not empty                                 |
| `[ -L F ]`              | F is a symbolic link                           |
| `[ A -nt B ]`           | A is newer than B; `-ot` older                 |
| `[ -t FD ]`             | FD is a terminal                               |
| `[ ! T ]`               | T does not hold                                |
| `[ T -a U ]` `[ T -o U ]` | both hold; either does                       |

```ash
touch here
[ -f here ] && echo file          # -> file
[ -d here ] || echo no directory  # -> no directory
[ 10 -gt 9 ] && echo number       # -> number
[ 10 \< 9 ] && echo string        # -> string
[ -z "$unset" ] && echo empty     # -> empty
[ a = a -a ! b = c ] && echo both # -> both
```

### set

| Option            | Effect                                              |
|-------------------|-----------------------------------------------------|
| `set -e`          | the shell exits when a command fails                |
| `set -u`          | an unset parameter is an error                      |
| `set -x`          | each command is traced on standard error            |
| `set -f`          | no pathname matching                                |
| `set -a`          | every variable assigned is exported                 |
| `set -C`          | `>` does not write over a file                      |
| `set -o pipefail` | a pipeline fails when any part does                 |
| `set +e`          | `+` turns an option off                             |

```ash
false | true
echo $?                           # -> 0
set -o pipefail
false | true
echo $?                           # -> 1

set -C
echo a > kept
echo b > kept 2> /dev/null || echo refused    # -> refused
echo c >| kept
cat kept                          # -> c

set -f
echo *                            # -> *
```

## Differs

| Here                                        | In bash                        |
|---------------------------------------------|--------------------------------|
| POSIX's language, and no more               | arrays, `[[ ]]`, `{a,b}`       |
| `trap 'CMD' INT` is refused                 | runs CMD on the signal         |
| no `jobs`, `fg`, `bg`                       | job control                    |
| `test` has no `-r`, `-w`, `-x`, `-ef`       | has them                       |
| `command -p` is refused                     | uses a default PATH            |
| a `( )` that outlives the shell can lose output | does not                   |

## More

| Where                            | What                               |
|----------------------------------|------------------------------------|
| `README.md`                      | each feature in full; what is not built |
| `tests/specs/`                   | one case a behaviour               |
| `make card`                      | runs every script on this page     |
