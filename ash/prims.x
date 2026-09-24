; # x-ash -- a POSIX shell on x-lang
;
; ## ash/prims.x -- the platform layer, under the names ash was written against
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; ash reaches past x-lang in two directions -- it registers its own tokenizer
; types on an isolated base, and it forks, execs and dup2s. Both surfaces are
; classes now: (Base make-tok) and (Base make-type) for the tokenizer base, and
; the Sys class for the process and file doors. This file forwards to them
; under the names tokens.x and eval.x are written against, so those two files
; read as a tokenizer and a shell rather than as platform glue.

; THE DIALECT IS HELIUM, so the doors this file forwards to arrive by NAME.
; lang.xon carries the arithmetic; the operative half is here.  x/sys/posix is
; the Sys class -- fork, exec, wait, pipe, dup2, the open family, getenv and
; chdir -- and importing it at the top of the platform layer is what makes an
; unsatisfiable requirement fail at ACQUISITION rather than at the first
; pipeline.  Base, Str8, Io and List are core; only this one is an opt-in.
(import x/sys/posix)
; x/sys/file is the File class: stat (which is what `test -f` and `test -d`
; actually ask) and read-all (which is what `.` needs to source a script).
; Sys alone answers only "does this path exist", and a shell that cannot tell
; a directory from a file has no working `test`.
(import x/sys/file)

(provide ash/prims
  make-token-base base-make-type token-read-string
  first-int set-first-int! convert buffer-token
  char->integer integer->char string-length string-ref substring string-append
  string=? string? make-string list->string length reverse append map filter
  take drop nth last fx<? fx+
  sh-fork sh-exec sh-wait sh-exit sh-getpid
  sh-open-read sh-open-write sh-open-append sh-open-rdwr sh-open-new
  sh-open-existing sh-close sh-dup2 sh-pipe
  sh-getenv sh-setenv sh-unsetenv sh-environ sh-chdir sh-getcwd
  sh-path-kind sh-path-size sh-path-mode sh-path-lkind sh-path-mtime
  sh-read-file sh-read-line sh-read-line-fd
  sh-read-hit-eof sh-read-all-fd sh-list-dir sh-sort-strings sh-fd-write)

; --- The tokenizer base ------------------------------------------------------
; (Base make-tok) is the isolated, type-free tokenizer base: ash's `;` is a
; separator and its `#` a comment because no sexp types are registered on it.
; (Base make) would arrive with the built-in sexp types already registered, so
; shell tokens would compete with them by score -- `a|b` as one word, ash's
; INTEGER type colliding with the platform's -- and report the wrong tokens.
(def make-token-base (fn (_) (Base make-tok)))

; (Base make-type TARGET NAME HANDLERS) -- cross-base registration, which is
; exactly what base-make-type was.  The name is a STRING now; ash passes
; strings already.
(def base-make-type
  (fn (_ base name handlers) (Base make-type base name handlers)))

; (prim-ref 'tok 'read-str), the same reference lib/x/repl/ansi.x and
; lib/x/reader/lit-reader.x hold. It takes the raw base, and (Base make-tok)
; hands back a wrapped instance -- passing the instance crashes the prim on any
; input -- so the unwrap lives here, once.
(def %token-read-str (prim-ref (lit tok) (lit read-str)))
(def token-read-string
  (fn (_ base input) (%token-read-str (Base raw-of base) input)))

; The consumed token's text, inside a reader callback. The namespace is `buf`
; and the member is `tok` (not `token`). Unbound, this raises inside a
; tokenizer callback, which surfaces as a crash rather than a message.
(def buffer-token (prim-ref (lit buf) (lit tok)))

; --- Tokenizer int cells -----------------------------------------------------
; These are real C cells built by the engine, so the raw-word accessors are
; correct here: %cell-int / %set-cell-int! read and write the machine word in
; their first slot. The same two names are wrong on an ordinary (list 0), whose
; slot 0 holds an object pointer the collector would then follow to the
; integer's value (x-lang#522); the distinction is which object you hold, and
; here it is the engine's.
(def first-int %cell-int)
(def set-first-int! %set-cell-int!)

; --- convert -----------------------------------------------------------------
; No explicit receiver: every call fills the `_` slot implicitly, apply
; included, so passing one by hand shifts every argument along and the
; conversion answers nil.
(def %cvt (prim-ref (lit convert) (lit to)))
(def convert (fn (_ v target . extra) (apply %cvt (pair v (pair target extra)))))

; The handful of Scheme-ish names tokens.x and eval.x reach for, spelled
; through the classes that own them now. ash is not a Scheme -- there is no
; alias layer -- so these are only what those two files actually call.
;
; char->integer is the direct prim, not the convert dispatcher: (%cvt c %int)
; walks the type's from/to alists and allocates, and %sh-word-break? calls this
; six times per character inside a tokenizer callback, where a collection
; mid-token is a hazard. lib/x/reader/analyser.x holds the same reference:
;   (def %char->integer (prim-ref (lit char) (lit ->int)))
(def char->integer (prim-ref (lit char) (lit ->int)))
; Conversions are keyed on the source type, so the pair is (char ->int) and
; (int ->char). (char from-int) exists as a Char method but not as a catalog
; member, and prim-ref answers nil for a missing member -- which would reach
; the reader as a garbage int rather than an error.
(def integer->char (prim-ref (lit int) (lit ->char)))
; Byte doors, not class dispatch. These four are the expansion walk's inner
; loop -- every unquoted word is scanned three times, a byte at a time -- and
; the raw primitives cost about a fifth of the heap that (Str8 ref)/(Str8 sub)
; dispatch does per call (measured at 1,000 calls each with (heap count)). A
; shell in the C locale is a byte tool; x-awk made the same move (awk/prims.x).
; Bound to the primitive directly where the argument order already agrees; only
; substring (Scheme's [start, end) against the primitive's (start, length)) and
; the variadic string-append keep a wrapper.
(def string-length (prim-ref (lit str) (lit byte-len)))
(def string-ref (prim-ref (lit str) (lit byte-ref)))
(def %str-byte-sub (prim-ref (lit str) (lit byte-sub)))
(def substring (fn (_ s a b) (%str-byte-sub s a (- b a))))
(def %str-append-2 (prim-ref (lit str) (lit append)))
(def string-append (fn (_ . ss) (%ash-str-append ss)))
(def %ash-str-append
  (fn (self ss)
    (if (null? ss)
      ""
      (if (null? (rest ss)) (first ss) (%str-append-2 (first ss) (self (rest ss)))))))
(def string=? (fn (_ a b) (str=? a b)))
(def string? (fn (_ s) (str? s)))
(def make-string (fn (_ n c) (Str8 make n c)))
(def list->string (fn (_ l) (if (null? l) "" (%cvt l %string))))

; Integer doors, for the scans the byte doors feed.  The platform's `<` is a
; guarded wrapper and its `>=` a wrapper around that -- a few hundred heap
; objects a comparison, asked per character -- where the primitive allocates
; nothing.  A character compares as its code point, and a bignum still reaches
; its own handler.
;
; They are unchecked: a nil operand crashes the process instead of raising, and
; a sum or product past a machine word wraps rather than carrying into a bignum.
; They are for operands that cannot be nil -- a position, a length, a character
; out of string-ref or handed to a reader hook -- and never for a value from
; the script, which converts to nil when it is not a number.  `>=` is spelled
; (not (fx<? a b)).
(def fx<? (prim-ref (lit int) (lit <)))
(def fx+ (prim-ref (lit int) (lit +)))
(def fx* (prim-ref (lit int) (lit *)))

; REVERSE AND list->string RUN INSIDE READER CALLBACKS, so neither may be a
; class dispatch.  lib/x/reader/analyser.x states the rule outright: reader
; context callers "must fetch them raw ... NOT (Analyser accept ...) (class
; dispatch allocates, hazardous mid-reader-callback)".
;
; (List reverse ...) is exactly such a dispatch, and ash's quoted-string
; readers call reverse and list->string at the closing quote.  With the
; dispatching version '' tokenized fine and 'a' produced (tok-sq ()) -- the
; accumulation silently became nil, with no error.  Plain recursion over the
; pair prims allocates one cons per element and dispatches nothing.
(def reverse
  (fn (self l) (%ash-rev l ())))
(def %ash-rev
  (fn (self l acc)
    (if (null? l) acc (self (rest l) (pair (first l) acc)))))

; The rest of the list vocabulary walks pairs too, for cost.  A (List ...)
; method enters through fold and from-seq -- 25,000 to 40,000 heap objects a
; call before it reaches an element -- and the evaluator calls these for every
; word and every command: `[ a = b ]` alone asked for a length, a take and a
; last.  Every caller holds a proper list, so none needs the sequence
; conversion the class exists to provide.  A count here is a position in such
; a list -- never nil, never a bignum -- so it steps on the integer doors.
(def length (fn (_ l) (%ash-len l 0)))
(def %ash-len
  (fn (self l n) (if (null? l) n (self (rest l) (fx+ n 1)))))

(def append (fn (_ a b) (%ash-rev (%ash-rev a ()) b)))

(def map (fn (_ f l) (%ash-rev (%ash-map f l ()) ())))
(def %ash-map
  (fn (self f l acc)
    (if (null? l) acc (self f (rest l) (pair (f (first l)) acc)))))

(def filter (fn (_ p l) (%ash-rev (%ash-filter p l ()) ())))
(def %ash-filter
  (fn (self p l acc)
    (match
      ((null? l) acc)
      ((p (first l)) (self p (rest l) (pair (first l) acc)))
      (#t (self p (rest l) acc)))))

(def take (fn (_ n l) (%ash-rev (%ash-take n l ()) ())))
(def %ash-take
  (fn (self n l acc)
    (match
      ((not (fx<? 0 n)) acc)
      ((null? l) acc)
      (#t (self (fx+ n -1) (rest l) (pair (first l) acc))))))

(def drop
  (fn (self n l)
    (match
      ((not (fx<? 0 n)) l)
      ((null? l) l)
      (#t (self (fx+ n -1) (rest l))))))

; Past the end is nil rather than a raise; every caller checks the length
; first.
(def nth
  (fn (_ n l) (let ((tail (drop n l))) (if (null? tail) () (first tail)))))

; %sh-bracket uses `last`, so it must be bound here or `[ x = x ]` raises
; Unbound.
(def last
  (fn (self l)
    (match
      ((null? l) ())
      ((null? (rest l)) (first l))
      (#t (self (rest l))))))
(def set-first! %set-first!)

; --- The shell's syscalls ----------------------------------------------------
; Forwards to the Sys and File classes, which carry every process and file
; door, under a name a shell recognises. The sh- prefix is kept because eval.x
; reads as a shell for it: (sh-dup2 fh fd) in a redirection is the shell's
; vocabulary, not the platform's.
;
; Each method is resolved once, through method-of, the door class.x keeps for
; hot paths.  A (Sys dup2 ...) call finds its method in the class's table
; every time, and two methods of one class in turn -- dup2 and close, which
; every redirection runs -- cost ~9K objects a call that way, against ~1.4K
; for the method resolved.
(def %sys-fork (method-of Sys (lit fork)))
(def %sys-exec (method-of Sys (lit exec)))
(def %sys-wait (method-of Sys (lit wait)))
(def %sys-exit (method-of Sys (lit exit)))
(def %sys-getpid (method-of Sys (lit getpid)))
(def %sys-close (method-of Sys (lit close)))
(def %sys-dup2 (method-of Sys (lit dup2)))
(def %sys-pipe (method-of Sys (lit pipe)))
(def %sys-getenv (method-of Sys (lit getenv)))
(def %sys-setenv (method-of Sys (lit setenv)))
(def %sys-unsetenv (method-of Sys (lit unsetenv)))
(def %sys-environ (method-of Sys (lit environ)))
(def %sys-chdir (method-of Sys (lit chdir)))
(def %sys-getcwd (method-of Sys (lit getcwd)))
(def %sys-fd-read (method-of Sys (lit fd-read)))
(def %sys-fd-write (method-of Sys (lit fd-write)))
(def %file-open (method-of File (lit open)))
(def %file-stat (method-of File (lit stat)))
(def %file-lstat (method-of File (lit lstat)))
(def %file-read-all (method-of File (lit read-all)))
(def %file-list-dir (method-of File (lit list-dir)))
(def %assoc-entry (method-of Assoc (lit entry)))
(def %str8-join (method-of Str8 (lit join)))

; A word's pieces are joined each time one of its fields closes, and a field
; is most often one piece, which Str8 join answers as it is; asking first
; skips the call.
(def %ash-join
  (fn (_ sep pieces)
    (match
      ((null? pieces) "")
      ((null? (rest pieces)) (first pieces))
      (#t (%str8-join Str8 sep pieces)))))

; A number's text.  A fixnum is written by %number->str, the platform's own
; number printer, which the printer uses for every integer it writes: a tenth
; of what `convert` costs.  It divides with the integer primitives, so any
; other number -- a bignum out of arithmetic -- goes through `convert`.
(def %ash-type-of (prim-ref (lit type) (lit of)))
(def %ash-int-type (%ash-type-of 0))
(def %ash-number->str
  (fn (_ n)
    (if (eq? (%ash-type-of n) %ash-int-type) (%number->str n) (convert n %string))))

(def sh-fork (fn (_) (%sys-fork Sys)))
(def sh-exec (fn (_ path args) (%sys-exec Sys path args)))
(def sh-wait (fn (_ pid) (%sys-wait Sys pid)))
(def sh-exit (fn (_ status) (%sys-exit Sys status)))
(def sh-getpid (fn (_) (%sys-getpid Sys)))

; A redirection's file is opened by (File open), which hands the permission
; bits to the kernel: a file it creates is 0666 (438) less the umask, as a
; shell's is, and a file already there keeps its mode.  (Sys open-write) and
; (Sys open-append) set every file they open to 0666.
;
; Each open's flags are ORed together once, from the platform's own table,
; (File file-modes), as its documentation has it: a list of names handed to
; (File open) is folded into the same number at every call.
(def %sh-open-flags
  (fn (self names acc)
    (if (null? names)
      acc
      (self (rest names)
            (| acc (first (Assoc get (first names) (File file-modes))))))))

(def %sh-o-read (%sh-open-flags (list (lit rdonly)) 0))
(def %sh-o-write (%sh-open-flags (list (lit wronly) (lit creat) (lit trunc)) 0))
(def %sh-o-append (%sh-open-flags (list (lit wronly) (lit creat) (lit append)) 0))
(def %sh-o-rdwr (%sh-open-flags (list (lit rdwr) (lit creat)) 0))
(def %sh-o-new (%sh-open-flags (list (lit wronly) (lit creat) (lit excl)) 0))
(def %sh-o-existing (%sh-open-flags (list (lit wronly)) 0))

(def sh-open-read (fn (_ path) (%file-open File path %sh-o-read)))
(def sh-open-write (fn (_ path) (%file-open File path %sh-o-write 438)))
(def sh-open-append (fn (_ path) (%file-open File path %sh-o-append 438)))
(def sh-open-rdwr (fn (_ path) (%file-open File path %sh-o-rdwr 438)))
; For `set -C`: a file created only when none is there, and one already there
; opened as it is.
(def sh-open-new (fn (_ path) (%file-open File path %sh-o-new 438)))
(def sh-open-existing (fn (_ path) (%file-open File path %sh-o-existing)))
(def sh-close (fn (_ fd) (%sys-close Sys fd)))
(def sh-dup2 (fn (_ from to) (%sys-dup2 Sys from to)))

; (Sys pipe) answers a (read-fd . write-fd) pair, which is what
; %sh-pipe-create expects.
(def sh-pipe (fn (_) (%sys-pipe Sys)))

(def sh-getenv (fn (_ name) (%sys-getenv Sys name)))
(def sh-setenv (fn (_ name value) (%sys-setenv Sys name value)))
(def sh-chdir (fn (_ dir) (%sys-chdir Sys dir)))

(def sh-unsetenv (fn (_ name) (%sys-unsetenv Sys name)))
; The whole environment as "NAME=VALUE" strings, which is what `export -p`
; lists.
(def sh-environ (fn (_) (%sys-environ Sys)))
(def sh-getcwd (fn (_) (%sys-getcwd Sys)))

; --- What `test` needs to know about a path ------------------------------
; The kind symbol ('file, 'dir, 'link, ...) or nil when the path is not there
; at all -- so one call answers -e, -f and -d, and a missing path is a nil
; rather than a raise.  File stat raises a tag 'io Err on failure, which for
; a shell test is an ANSWER, not an error.
(def sh-path-kind
  (fn (_ path)
    (guard (_ ()) (rest (%assoc-entry Assoc (lit kind) (%file-stat File path))))))

(def sh-path-size
  (fn (_ path)
    (guard (_ 0) (rest (%assoc-entry Assoc (lit size) (%file-stat File path))))))

; The permission bits, or 0 for a path that is not there -- what `command -v`
; asks to tell a program on PATH from a file of the same name.
(def sh-path-mode
  (fn (_ path)
    (guard (_ 0) (rest (%assoc-entry Assoc (lit mode) (%file-stat File path))))))

; The kind of the path itself, a symbolic link reporting 'link rather than
; its target's kind -- what `test -L` asks -- or nil when nothing is there.
(def sh-path-lkind
  (fn (_ path)
    (guard (_ ())
      (rest (%assoc-entry Assoc (lit kind) (%file-lstat File path))))))

; The last modification, in whole seconds, or nil when nothing is there --
; what `test -nt` and `-ot` compare.
(def sh-path-mtime
  (fn (_ path)
    (guard (_ ())
      (rest (%assoc-entry Assoc (lit mtime) (%file-stat File path))))))

(def sh-read-file (fn (_ path) (%file-read-all File path)))

; --- One line from the current input, or nil at EOF ----------------------
; bytes->str, NOT list->string: the accumulator holds raw input BYTES, and the
; utf8-aware conversion would re-encode anything >= 128 and corrupt a UTF-8
; filename on its way to exec.  EOF with a partial line is still a line -- a
; script whose last line has no trailing newline must run.
;
; ONE COPY, used by both the `read` builtin and the session loop in
; ash/repl.x: they are the same question asked from two places.
(def %sh-read-char (prim-ref (lit io) (lit read-char)))

(def sh-read-line
  (fn (_)
    (def go
      (fn (self acc)
        (let ((ch (%sh-read-char)))
          (if (null? ch)
            (if (null? acc) () (bytes->str (reverse acc)))
            (if (= ch 10)
              (bytes->str (reverse acc))
              (self (pair (integer->char ch) acc)))))))
    (go ())))

; --- One line straight off a DESCRIPTOR ----------------------------------
; The `read` builtin cannot use the reader above, and the difference is the
; whole reason both exist.  sh-read-line goes through the ENGINE's reader,
; which is right for the session loop -- that reader is what the prompt is
; already positioned in.  But the engine's reader is bound to the stream it
; was opened on, not to whatever fd 0 currently names, so
;
;   read a b < input.txt
;
; dup2s the file onto fd 0 and the engine reader never notices: both variables
; came back empty.  A shell's `read` reads its STANDARD INPUT, redirections
; included, so it has to ask the descriptor.
;
; ONE BYTE AT A TIME, which is not the pessimisation it looks like: reading
; ahead would swallow bytes past the newline that belong to the NEXT reader of
; that descriptor -- the engine's own, when input is a script.  A shell's read
; is specified to consume exactly the line it returns, and this is what that
; costs.
; Set when the last read ended at end of input rather than at a newline.  The
; `read` builtin answers a non-zero status in that case even though it has a
; line to assign, which is what stops `while read line` on a file whose last
; line has no terminator.
(def sh-read-hit-eof ())

(def sh-read-line-fd
  (fn (_ fd)
    (def go
      (fn (self acc)
        (let ((b (%sys-fd-read Sys fd 1)))
          (if (null? b)
            (do
              (set! sh-read-hit-eof #t)
              (if (null? acc) () (bytes->str (reverse acc))))
            (let ((c (first b)))
              (if (= c 10)
                (bytes->str (reverse acc))
                (self (pair (integer->char c) acc))))))))
    (set! sh-read-hit-eof ())
    (go ())))

; --- Everything a descriptor has to give, to EOF -------------------------
; What command substitution reads back from its child.  Chunks are collected
; reversed and joined once: appending each 4K read onto a growing accumulator
; would copy the whole of it every time, which is quadratic in the output of
; a `$(cat big-file)`.
(def %sh-join-chunks
  (fn (self chunks acc)
    (if (null? chunks)
      acc
      (self (rest chunks) (append (first chunks) acc)))))

(def sh-read-all-fd
  (fn (_ fd)
    (def go
      (fn (self chunks)
        (let ((b (%sys-fd-read Sys fd 4096)))
          (if (null? b) chunks (self (pair b chunks))))))
    (bytes->str (%sh-join-chunks (go ()) ()))))

; --- A directory's entry names, sorted -----------------------------------
; What pathname expansion matches against.  `.` and `..` are already excluded
; by File list-dir.  An unreadable or missing directory answers the empty list
; rather than raising: a glob that matches nothing is not an error, it is a
; glob that matches nothing.
(def sh-sort-strings
  (fn (_ xs) (List sort (fn (_ a b) (Str8 <? a b)) xs)))

(def sh-list-dir
  (fn (_ path) (sh-sort-strings (guard (_ ()) (%file-list-dir File path)))))

; Raw write to a descriptor -- what a here-document's writer child pushes into
; the pipe.  (Sys fd-write) answers the byte count; the shell has no use for it.
(def sh-fd-write (fn (_ fd text) (%sys-fd-write Sys fd text)))
