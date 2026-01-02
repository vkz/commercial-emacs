# clemacs — Option B (SBCL-hosted Emacs, C as substrate library)

This document describes the “ambitious” path: SBCL is the host runtime and owns
the Lisp engine *and* (eventually) the canonical object model, while the Emacs C
code becomes a substrate library called from CL.

Goal: maximize long-term architectural clarity and leverage SBCL’s compiler/GC,
accepting that it requires more immediate C-side change.

---

## Facts observed in the current C code (why Option B is hard)

### 1) `Lisp_Object` is not “just an API” today — it is the substrate’s bloodstream

- C code relies deeply on:
  - tagging scheme and `XTYPE/XPNTR` style macros,
  - pervasive `Lisp_Object` return values from primitives,
  - runtime invariants inside `struct Lisp_*` layouts.

In other words, it’s not just the evaluator that uses `Lisp_Object`; the editor
subsystems do too.

### 2) Emacs GC is conservative and is wired to Emacs’ own allocations/threads

`src/alloc.c` implements conservative stack scanning (`mark_maybe_pointer`) by
checking words against known Emacs allocation regions (cons blocks, string
blocks, vector blocks, etc.) and “making whole” interior pointers.

Implication for Option B:

- If we stop allocating Emacs-managed `Lisp_Object` blocks, Emacs GC can no
  longer be the authority for Lisp object lifetimes.
- If we keep allocating them, we keep Emacs GC (and most of the value model),
  which undermines the “SBCL owns GC and values” ambition.

### 3) Builtins/primitives are a startup/dump-time mechanism, not just functions

`DEFUN` defines static subr records in a dedicated section and `defsubr` wires
them into the runtime at init time. This is entangled with pdump/initialization.

Implication: “primitives go straight to CL” is feasible, but it requires a new
replacement mechanism for startup registration and for any code expecting subr
objects.

---

## Option B architecture (SBCL host, C substrate library)

### One-sentence summary

SBCL starts first, loads a CL-defined “Emacs Lisp dialect” layer, loads (or
links) a C substrate library, then runs the command loop with SBCL in charge of
evaluation, compilation, and GC.

### Process ownership

- Entry point is CL (a `main` in SBCL, or a delivered image).
- The C code is built as a shared library (or linked object set) with a
  deliberately small and stable exported C API.

### Canonical value representation (target end-state)

- CL values are canonical:
  - conses are CL conses,
  - vectors are CL vectors,
  - strings are CL strings (or CL strings + property/interval sidecars),
  - symbols are CL symbols (likely in a dedicated package), or custom structs.
- The C substrate does **not** traffic in `Lisp_Object` internally (or only does
  so behind a strict boundary while being migrated).

This is the core bet of Option B.

---

## There are really two Option B sub-variants (pick deliberately)

Option B is large enough that it helps to name two concrete approaches.

### B1: “Handle-based C API” (best-aligned with SBCL-canonical values)

Rewrite the C substrate to accept opaque handles rather than `Lisp_Object`.

- C API takes `emx_value`-like handles (opaque pointers/integers).
- C never inspects Lisp values directly; it calls back into CL for operations
  (predicates, extracting integers/strings, calling closures, etc.).
- SBCL GC owns lifetimes; C must register handles it keeps across calls (rooting
  on the SBCL side, or using pinned objects / stable pointers).

Pros:
- Conceptually clean: one GC, one value model, one evaluator.

Cons:
- Requires touching a lot of C code early (mechanical but large).
- Performance needs care: lots of cross-boundary calls if naïvely designed.

### B2: “Two-heap bridge” (keeps `Lisp_Object` longer, undermines ambition)

Keep `Lisp_Object` for substrate objects and expose them to CL as foreign values.

- CL wraps `Lisp_Object` as foreign tagged values.
- Emacs GC still exists for those values.

Pros:
- Lower immediate C rewrite cost than B1.

Cons:
- Two GCs, two value models, complex rooting correctness.
- Harder to “lean into CL semantics” fully because core objects remain Emacs
  objects.

If the stated goal is “SBCL does its magic with optimizations and GC”, B1 lines
up more directly; B2 is primarily a transitional compromise.

---

## What must change on the C side (Option B, especially B1)

### 1) Replace the pervasive `Lisp_Object` interfaces

Most existing C primitives and many internal helpers use `Lisp_Object`. This
isn’t just “the evaluator API” — it’s the editor’s internal data plumbing.

For B1, the core move is a *new substrate API boundary* that:

- uses C-native types for hot-path substrate logic (ints, sizes, pointers), and
- uses opaque handles for “Lisp values”, with *no* direct tagging/macros on the
  C side.

This is likely a large but mechanical refactor: function signatures, helper
macros, and call sites across many `src/*.c` files.

Practical technique to keep it controlled:

- introduce a single new “value handle” type early (`emx_value`),
- convert one module at a time to accept/return handles,
- keep the old `Lisp_Object` entrypoints temporarily as shims that marshal to
  the new API (until removed).

### 2) Replace the Lisp-engine entrypoints (`Ffuncall`/`Feval`/`Fapply`)

Today, most C→Lisp calls collapse through `Ffuncall` and friends (`CALLN`,
`call0`, `call1`, etc. in `src/lisp.h`), which then dispatch in `src/eval.c`.

In Option B, the evaluator is owned by SBCL, so:

- “calling Lisp” becomes “calling into SBCL” (via a stable embedding API).
- error/nonlocal-exit propagation must be redefined:
  - C detects fatal conditions / quit and raises them to CL as conditions (or
    returns a tagged failure value that CL treats as a condition).

Design goal: keep the substrate from needing to know “macro vs function vs
special form” — it should only be able to call “a callable handle”.

### 3) Replace or rebuild the builtin primitive registration mechanism

Current mechanism (facts):

- `DEFUN` creates a static subr record (with special section placement on
  darwin) and a C function.
- `defsubr(&Sfoo)` registers it at init time.

For Option B, we want most “primitives” to be CL functions/macros instead.
Therefore we need a replacement story for:

- startup registration of primitives,
- docstrings/help metadata (currently partially in C),
- any code expecting subr identity/layout.

Possible approaches:

1. **CL-owned primitive registry**
   - primitives are defined in CL and registered in a CL table.
   - substrate functions that need “callbacks” receive handles from CL.

2. **Hybrid: keep a thin set of C subrs temporarily**
   - keep a minimal C shim layer only where unavoidable (TTY IO, low-level
     sysdep), and progressively delete it.

Either way, “C defines the global Lisp namespace” is no longer true; CL does.

### 4) Untangle `specpdl`/unwind-protect responsibilities

Emacs uses `specpdl` + `record_unwind_protect` pervasively for cleanup and
dynamic binding. In Option B:

- CL `unwind-protect` should own Lisp-level dynamic extent and bindings.
- C can still use its unwind machinery for C resource cleanup (fds, malloc,
  terminal modes), but it should not be the “Lisp dynamic environment”.

That implies we must identify C code paths that assume:

- dynamic binding is managed via `specbind` / `unbind_to`,
- evaluation is happening under that same mechanism.

Those become refactor targets.

---

## GC and lifetime management in Option B

### Key fact: Emacs GC is conservative and tied to Emacs allocations

In `src/alloc.c`, GC roots are found by conservative scanning (`mark_maybe_pointer`)
over stacks/regions that Emacs knows about, and by walking Emacs allocation
regions (cons/string/vector/symbol blocks, etc.). Allocation uses block pools,
and sweep reconstructs free lists and may return some free blocks to `lisp_free`.

Therefore:

- If we want SBCL GC to be authoritative, we must stop relying on Emacs GC for
  Lisp value lifetime.
- That pushes us toward B1 (handle-based substrate) rather than B2 (two heaps).

### What SBCL GC needs from the C substrate

If C holds references to CL objects across calls, we need stable references.
Typical patterns:

1. **Stable handle table (portable, straightforward)**
   - CL stores objects in a global handle table; C stores integer handles.
   - All cross-boundary calls exchange handles, not raw object pointers.
   - CL controls when handles are released (explicit free or GC-driven finalizer).

2. **Pinned/immobile objects (fast but SBCL-sensitive)**
   - C holds raw pointers to pinned SBCL objects.
   - Requires a carefully defined pin/unpin API and clarity on when pinning is
     safe/performance acceptable.

3. **Foreign objects as canonical for substrate-heavy structures**
   - For buffers/windows/markers, allocate C structs and give CL wrappers.
   - SBCL finalizers can reclaim C resources when wrappers die.

### What happens to Emacs “Lisp object” finalizers and weak pointers?

Emacs GC includes:

- a finalizer queue (`queue_doomed_finalizers` / `run_finalizers`), and
- weak-ish concepts (e.g., markers unchained when buffers are swept).

In Option B, equivalents must exist:

- CL conditions/finalizers (or explicit lifetime management) for objects with
  side effects,
- weak references for caches and marker-like semantics.

This is a real workload item, not an afterthought.

---

## Allocation/destruction patterns and “arena allocation” on modern machines

### Observed: Emacs Lisp allocation is already slab/pool-based

Even today:

- conses are allocated from blocks and reclaimed to free lists (`Fcons` and
  `sweep_void` in `src/alloc.c`),
- strings and string payloads are block-managed,
- vectors are block-managed (small) or separately allocated (large).

So the Lisp allocator is already an “arena-like” system.

### What we can do today (without changing architecture)

- Raising `gc-cons-threshold` / `gc-cons-percentage` changes GC frequency but
  does not remove the need for GC or rooting correctness.

### In Option B, “arenas” mainly matter for C-only scratch allocations

If SBCL owns Lisp values, Emacs’ current Lisp allocators should shrink or go
away; arenas might help for:

- redisplay scratch memory,
- transient C parsing/formatting structures,
- per-command temporary allocations.

But this should be profile-driven once we have an interactive loop.

---

## Where Option B pays off: Elisp-as-CL-dialect becomes real

Option B’s main language-level upside:

- “Elisp” becomes a CL dialect:
  - CL special forms/macros are the default,
  - an `ELISP` package provides compatibility names, wrappers, and a small set
    of semantic adapters,
  - syntax deltas are handled by a minimal reader/prepass.

But: the substrate contract (buffers, keymaps, markers, etc.) remains the
hard half, and must be planned explicitly via the substrate API.

---

## Risks (Option B)

- **Scope/complexity**: large mechanical C refactor to break `Lisp_Object`
  dependencies.
- **Boot risk**: you may not get a runnable editor until late unless milestones
  ensure early interactive checkpoints.
- **Interop performance**: a too-chatty CL↔C API can become the bottleneck.
- **Dump/startup**: existing pdumper and builtin init assumptions likely need
  replacement or deferral.
- **Debugging**: cross-runtime failures are harder to diagnose.

---

## Milestones for Option B (designed to keep progress measurable)

### Milestone 0: define the substrate API boundary (paper first)

Deliverables:

- A list of “must-have substrate services” for initial boot (TTY IO, buffers,
  minimal display, input, filesystem, minimal processes/timers).
- A proposed C API for those services that does *not* mention `Lisp_Object`.
- A first-pass mapping of “what used to be a C primitive” into:
  - CL primitive (preferred),
  - substrate API function (when inherently C/system-bound).

Acceptance:

- We can explain how command dispatch works with SBCL in charge: where keymaps
  live, how commands are called, and how quit/errors propagate.

### Milestone 1: minimal substrate library callable from SBCL

Acceptance:

- SBCL starts, loads CL code, calls a trivial substrate function, gets a result.
- Substrate can call back into CL for a trivial hook/callback.

### Milestone 2: “hello command loop” (TTY)

Acceptance:

- A minimal loop exists (CL-driven is fine) that can:
  - read a key,
  - dispatch to a CL command,
  - update the TTY display.

### Milestone 3: bootstrap enough Lisp + substrate for a usable editor core

Acceptance:

- Load a curated subset of `lisp/` translated to CL, enough to edit a file and
  run new-engine smoke tests.

---

## Open questions (Option B)

1. Which B-subvariant are we actually committing to (B1 vs B2)?
2. What is the minimal substrate API surface to reach “interactive TTY”?
3. How do we represent buffers/markers/text properties:
   - primarily in CL with C accessors?
   - primarily in C with CL wrappers?
4. Do we replace pdumper, reuse it, or defer it?
5. How do we map Emacs quit / nonlocal exits to CL conditions and back?
6. Performance: which operations must be hot in C vs hot in CL?
