## sh-eval `[` without its `]`

`[` is `test` with a closing `]` as its last word.  Without one it is a usage
error, 2, as it is in dash and bash, and the words are not tested.  A `]`
that is an operand, quoted or not, is only an operand.

Expectations match `/bin/sh` and `dash`.

### the statuses, in order

`[ a = a` and `[` alone have no `]`; `[ ]` tests nothing; `[ x ]` and
`[ "]" ]` test one word; `[ a = a ] ]` has one word too many.

```sh
(do (sh-eval "( ( [ a = a ) 2>/dev/null; printf '%s,' $?; ( [ ) 2>/dev/null; printf '%s,' $?; ( [ ] ); printf '%s,' $?; ( [ x ] ); printf '%s,' $?; ( [ \"]\" ] ); printf '%s,' $?; ( [ a = a ] ] ) 2>/dev/null; printf '%s,' $?; echo )") ())
```
---
    2,2,1,0,0,2,
