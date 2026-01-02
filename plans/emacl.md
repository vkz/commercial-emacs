# emacl — Option A (C-hosted Emacs, embed SBCL, gradual engine swap)

This document describes one plausible path for “SBCL-hosted Emacs Lisp” that
keeps the existing Emacs C runtime as the process host and swaps the Lisp
engine gradually.

Goal: maximize incremental progress and keep `mise run run` / `mise run test:*`
meaningful throughout the transition.

---

## Facts observed in the current C code (relevant to either option)

### Value representation: `Lisp_Object` is the universal ABI today

- Almost all Lisp-facing C code takes/returns `Lisp_Object` (tagged immediates
  + tagged pointers). See `src/lisp.h` and pervasive use in `src/*.c`.
- C primitives are either:
  - **special forms** (some in `src/eval.c`, e.g. `if`, `setq`, etc.), or
  - **subrs** (“built-in functions”) defined via `DEFUN(...)` and registered via
    `defsubr(&Sfoo)` during startup (`syms_of_*.c` style).

### GC: conservative marking + block allocators + sweep-to-free-lists

In this repo, GC is implemented in `src/alloc.c` and has three key properties:

1. **Conservative scanning of machine words**:
   - `mark_maybe_pointer` attempts to interpret arbitrary words as pointers into
     known Lisp allocations (cons blocks, vector blocks, symbol blocks, etc.).
   - This implies C locals holding `Lisp_Object` (or raw pointers into objects)
     are “roots” *only if they reside in memory regions the GC scans*.

2. **Pool/block allocators** for most Lisp heap objects:
   - conses: `Fcons` allocates from `cons_free_list` or `cons_blocks`.
   - strings: `allocate_string` allocates `struct Lisp_String` from
     `struct string_block`, and string payload from `struct sblock` chains (with
     “large string” handling).
   - vectors/pseudovectors: `allocate_vector` allocates from `vector_blocks`
     (small) or `large_vectors` (large); pseudovectors are vectors with tagged
     headers and traced prefix length.
   - symbols/floats/intervals similar: block allocators + free lists.

3. **Sweep phase**:
   - `garbage_collect` calls `gc_sweep` which reconstructs free lists and may
     return fully-free blocks back to `lisp_free` after a threshold (“more than
     two such blocks” pattern).
   - Some structures are treated specially (e.g., markers are “weak pointers”
     and are unchained when their buffers are swept).
   - There is a finalizer queue (`queue_doomed_finalizers` / `run_finalizers`).

### Calls into Lisp: C → `Ffuncall` / `Fapply` / `Feval` are chokepoints

- Many C call sites use `call0/call1/...` and `CALLN(...)` macros from
  `src/lisp.h`, which route to `Ffuncall` (and ultimately to dispatch via
  `funcall_general` in `src/eval.c`).
- The command loop in `src/keyboard.c` eventually does `call1 (Qcommand_execute, ...)`.
- `Feval` and `eval_form` are used in multiple C subsystems (menus, interactive
  calling, etc.), and return `Lisp_Object` to C.

### Builtins: `DEFUN` layout + `defsubr` registration matters to dump/startup

- `DEFUN` (in `src/lisp.h`) defines a static `union Aligned_Lisp_Subr` (placed
  into a dedicated linker section on darwin) and exposes a `Lisp_Object Fn(...)`
  entrypoint.
- `defsubr` registers subrs at init time.

Implication: any strategy that “removes” C subrs needs a replacement for this
startup story (and likely pdump assumptions).

---

## Option A architecture (C host, embedded SBCL)

### One-sentence summary

Keep Emacs as a C program with `Lisp_Object` and Emacs GC intact; embed SBCL as
an “alternate engine” that can (gradually) interpret/compile/execute Elisp, but
interoperates through `Lisp_Object` and existing C primitives.

### Process ownership

- `src/emacs.c:main` remains the process entrypoint.
- During init, C initializes SBCL and loads a CL system (or core image).

### Canonical value representation (during transition)

- `Lisp_Object` remains the canonical “data ABI” between C and CL.
- SBCL-side code manipulates *handles* to `Lisp_Object` values, and uses C
  functions to allocate/inspect them.

Rationale: avoids rewriting the C substrate first.

---

## The hard interop constraint: Emacs GC cannot see SBCL memory by default

Because Emacs uses conservative scanning over *known* stacks/regions, it will
not automatically treat SBCL’s heap (and possibly SBCL’s stacks) as a root set.

Therefore, if SBCL code keeps `Lisp_Object` values only in SBCL memory, Emacs
GC may reclaim the underlying objects “behind SBCL’s back”.

### Mitigation patterns (pick one early)

1. **C-rooted handles (straightforward baseline)**:
   - Provide a C “root stack / root table” that stores `Lisp_Object` values.
   - SBCL only holds small integers (indices/handles) that refer to that root
     table.
   - SBCL enters/exits dynamic extents with CL macros that push/pop root slots.

2. **Register SBCL roots with Emacs GC**:
   - Extend Emacs GC to scan SBCL’s root set (SBCL internals) or SBCL heap.
   - Likely brittle / SBCL-version dependent.

3. **Forbid Emacs GC during SBCL execution**:
   - Not realistic; many C primitives can allocate/GC and Emacs does GC in
     `Ffuncall`/`eval_form` paths.

Option A is viable only if we choose (1) or make (2) robust.

---

## How primitives/builtins work in Option A

### Transitional rule: “C primitives stay, CL calls them”

- Existing C `DEFUN` primitives remain authoritative initially.
- SBCL calls them via FFI (as ordinary C functions like `Fcons`, `Flist`, etc.).
- SBCL also needs helpers to create/intern symbols, build strings, etc.

This supports early bootstrapping: we can get a CL-based evaluator running
without immediately re-implementing buffers/windows/etc.

### Gradual migration (optional, later)

- Pure/algorithmic primitives can be reimplemented in CL over time.
- Substrate-heavy primitives remain in C longer.

But: the *interface* must remain `Lisp_Object` until a later “value ABI” shift.

---

## Where to integrate the engine (incrementally)

### Integration chokepoints

1. `Ffuncall` dispatch:
   - In `src/eval.c`, `funcall_general` routes to:
     - `funcall_subr` for C subrs
     - `funcall_lambda` for closures/bytecode/module functions
   - A natural incremental step is adding a new callable type (or a convention)
     that indicates “this function is implemented by SBCL”, then dispatch there.

2. `Feval` / `eval_form`:
   - Longer-term, make evaluation and macroexpansion happen in CL.

### Early acceptance criteria

- “CL-defined function is callable from the normal command path”:
  command loop → `command-execute` → `Ffuncall` → SBCL → returns `Lisp_Object`.

---

## Allocation/destruction patterns and “arena allocation” question

### What we have today

Emacs already behaves like a set of arenas/pools:

- Many Lisp allocations are slab/block-based (cons/string/vector/symbol/etc.).
- Most objects are reclaimed by GC sweep into free lists, and some empty blocks
  are returned to `lisp_free`.

So “add an arena” is unlikely to be a big win for Lisp objects, because the
existing allocator is already optimized for that pattern and relies on GC for
liveness.

### Where arenas might still help (if we choose)

- Non-Lisp, short-lived C allocations associated with parsing/printing or glue
  code, if there are known hot paths that churn `MEM_TYPE_NON_LISP`.
- But this is orthogonal to the CL integration choice; it can be explored after
  we can profile.

---

## Risks (Option A)

- Rooting correctness across SBCL ↔ Emacs GC boundaries (highest risk).
- Threading: Emacs has its own thread model (`src/thread.c`) and GC coordination;
  SBCL also has threading. Interactions need a policy (likely “SBCL single-thread
  inside Emacs” initially).
- Error/condition mapping: Emacs nonlocal exits, quit, and error symbols vs
  CL conditions.
- Build/packaging: linking SBCL, managing a core image, and ensuring repeatable
  out-of-tree builds.

---

## Open questions (Option A)

1. What is the minimal “root handle” API and invariants?
2. How do we represent “SBCL-defined callable” in `Lisp_Object`?
   - new pseudovector type vs reuse existing (module function?) representation.
3. What subset of Emacs startup Lisp must run to reach a prompt, and which C
   primitives are required?
4. Do we keep Emacs bytecode (`.elc`) support or switch entirely to CL
   compilation for `.el`?
