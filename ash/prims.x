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
  take drop nth last
  sh-fork sh-exec sh-wait sh-exit sh-getpid
  sh-open-read sh-open-write sh-open-append sh-close sh-dup2 sh-pipe
  sh-getenv sh-setenv sh-unsetenv sh-chdir sh-getcwd
  sh-path-kind sh-path-size sh-read-file sh-read-line sh-read-line-fd
  sh-read-all-fd sh-list-dir sh-sort-strings sh-fd-write)

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

(def length (fn (_ l) (List length l)))
(def append (fn (_ a b) (List append a b)))
(def map (fn (_ f l) (List map f l)))
(def filter (fn (_ p l) (List filter p l)))
(def take (fn (_ n l) (List take n l)))
(def drop (fn (_ n l) (List drop n l)))
(def nth (fn (_ n l) (List ref n l)))
; %sh-run-builtin's `[` arm forwards `last` to the platform, so it must be
; bound here or `[ x = x ]` raises Unbound.
(def last (fn (_ l) (List last l)))
(def set-first! %set-first!)

; --- The shell's syscalls ----------------------------------------------------
; One-line forwards to the Sys class, which carries every process and file door
; under a name a shell recognises. The sh- prefix is kept because eval.x reads
; as a shell for it: (sh-dup2 fh fd) in a redirection is the shell's
; vocabulary, not the platform's.
(def sh-fork (fn (_) (Sys fork)))
(def sh-exec (fn (_ path args) (Sys exec path args)))
(def sh-wait (fn (_ pid) (Sys wait pid)))
(def sh-exit (fn (_ status) (Sys exit status)))
(def sh-getpid (fn (_) (Sys getpid)))

(def sh-open-read (fn (_ path) (Sys open-read path)))
(def sh-open-write (fn (_ path) (Sys open-write path)))
(def sh-open-append (fn (_ path) (Sys open-append path)))
(def sh-close (fn (_ fd) (Sys close fd)))
(def sh-dup2 (fn (_ from to) (Sys dup2 from to)))

; (Sys pipe) answers a (read-fd . write-fd) pair, which is what
; %sh-pipe-create expects.
(def sh-pipe (fn (_) (Sys pipe)))

(def sh-getenv (fn (_ name) (Sys getenv name)))
(def sh-setenv (fn (_ name value) (Sys setenv name value)))
(def sh-chdir (fn (_ dir) (Sys chdir dir)))

(def sh-unsetenv (fn (_ name) (Sys unsetenv name)))
(def sh-getcwd (fn (_) (Sys getcwd)))

; --- What `test` needs to know about a path ------------------------------
; The kind symbol ('file, 'dir, 'link, ...) or nil when the path is not there
; at all -- so one call answers -e, -f and -d, and a missing path is a nil
; rather than a raise.  File stat raises a tag 'io Err on failure, which for
; a shell test is an ANSWER, not an error.
(def sh-path-kind
  (fn (_ path) (guard (_ ()) (rest (Assoc entry (lit kind) (File stat path))))))

(def sh-path-size
  (fn (_ path) (guard (_ 0) (rest (Assoc entry (lit size) (File stat path))))))

(def sh-read-file (fn (_ path) (File read-all path)))

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
            (if (null? acc) () (bytes->str (List reverse acc)))
            (if (= ch 10)
              (bytes->str (List reverse acc))
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
(def sh-read-line-fd
  (fn (_ fd)
    (def go
      (fn (self acc)
        (let ((b (Sys fd-read fd 1)))
          (if (null? b)
            (if (null? acc) () (bytes->str (List reverse acc)))
            (let ((c (first b)))
              (if (= c 10)
                (bytes->str (List reverse acc))
                (self (pair (integer->char c) acc))))))))
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
      (self (rest chunks) (List append (first chunks) acc)))))

(def sh-read-all-fd
  (fn (_ fd)
    (def go
      (fn (self chunks)
        (let ((b (Sys fd-read fd 4096)))
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
  (fn (_ path) (sh-sort-strings (guard (_ ()) (File list-dir path)))))

; Raw write to a descriptor -- what a here-document's writer child pushes into
; the pipe.  (Sys fd-write) answers the byte count; the shell has no use for it.
(def sh-fd-write (fn (_ fd text) (Sys fd-write fd text)))
