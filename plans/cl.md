<user>
Task is to reimplement emacs lisp implementation in emacs that’s basically C with one in common lisp. CL is chosen because the two are so close and much of elisp had been modeled after Common Lisp. If we implement elisp as embedding in CL effectively just a defmacro then we get full power of common lisp inside emacs. Idea is to have a sort of quasiquote for elisp with unquote escaping back into common lisp. Or (el … (cl … ) …) typical lisp trick to produce an embedded dsl that’s a compiler for it because of macro expansion. SBCL is assumed here.

Our first task is that of design and planning. Specifically do we use standard common lisp features only, CLOS, or open door to some well established libraries from the ecosystem. Goal is speed of development, modeling, debugging and performance! If some ext dependencies could help us minimize the effort and improve our implementation and its maintenance let’s hear them. Thoughts?
</user>

<assistant>
### Recommendation in one line

Use **standard Common Lisp + CLOS selectively**, and allow a **small, curated set of “infrastructure” libraries** that accelerate development (reader/AST, utilities, testing, debugging) while keeping the runtime core mostly dependency-light and performance-oriented on **SBCL**.

---

## 1) What to standardize on: CL vs CLOS vs ecosystem

### A. “CL-only” core (portable subset)

Use for:

* Fundamental data representation (conses, symbols, numbers, strings, vectors)
* Core evaluation, environments, macroexpansion pipeline
* Compilation to CL forms / SBCL compilation

Pros:

* Small surface area, fewer moving parts
* Easy to reason about performance (types/decls, specialized arrays, structs)
* Easier to keep “Elisp semantics” crisp instead of drifting into OO abstractions

Cons:

* You’ll reinvent some plumbing (reader tooling, utilities, collections, tests)

**Verdict:** Make this the default for the *semantic core*.

---

### B. CLOS as a tool, not a religion

Use CLOS for:

* Protocol boundaries where you want clean extensibility: “callable objects”, printing, debug views, doc/help systems
* Pluggable backends: e.g. buffer implementations, file/IO abstractions, display/redisplay later
* Generic operations that mirror Elisp polymorphism (sequence ops, print/read customization) *only where it pays*

Avoid CLOS for:

* Hot-path runtime representation of simple Elisp values (cons, fixnum-ish, strings, vectors)
* Tight loops in evaluator/bytecode interpreter/JIT path

**Verdict:** Use CLOS at module boundaries and for tooling, keep runtime values mostly structs/primitive CL types.

---

### C. Curated ecosystem dependencies (strongly recommended)

Allow dependencies if they:

1. reduce implementation time significantly,
2. are stable/widely used,
3. don’t infect the semantics of the Elisp core,
4. can be swapped out later.

Think: “developer velocity + debuggability” dependencies, not “framework” dependencies.

---

## 2) Concrete library shortlist (SBCL assumed)

### Tier 0: Build & portability scaffolding (basically free)

* **ASDF/UIOP**: project structure, filesystem ops, subprocesses. (UIOP comes with ASDF in most setups.)
* **Trivial-Features** (optional): if you end up gating SBCL-specific code cleanly.

### Tier 1: Utilities you will otherwise reimplement

* **Alexandria**: ubiquitous utility toolbox (hash-table helpers, sequences, destructuring helpers).
* **Serapeum** (optional): higher-level utilities; helpful, but you can start with Alexandria and add Serapeum later.

### Tier 2: Reader / syntax / embedded DSL ergonomics (high leverage for your “(el … (cl …) …)” plan)

You have two viable approaches:

**Approach 1 (recommended): compile Elisp syntax into an AST you control**

* **Named-Readtables**: lets you define an `elisp` readtable without global side effects.
* **Eclector**: robust reader toolkit (if you want to parse s-expressions into your own CST/AST with source locations).

This is valuable because:

* You’ll want **source locations** for error messages, debugging, and stepping.
* You may want to accept Elisp-ish reader extensions without fighting the standard CL reader.

**Approach 2: “EL-quasiquote” inside CL forms**

* You can implement `(el ...)` as a macro that consumes CL data, but if you also want Elisp-like syntax, you still end up writing reader tooling.
* If you go this route, **Named-Readtables** remains very useful.

**Net:** `named-readtables` is close to a must. `eclector` is a major speed boost if you care about good diagnostics early.

### Tier 3: Pattern matching for macroexpand/AST transforms (optional but speeds development)

* **Trivia** (or similar): pattern matching on AST nodes makes compiler passes and macroexpanders far less painful.

### Tier 4: Testing

* **FiveAM** or **Parachute**: pick one. You need heavy regression testing for Elisp compatibility.
* Add golden tests for macroexpansion and evaluation equivalence.

### Tier 5: Debugging / interactive development

* **SLY** (or SLIME) + **slynk/swank**: non-negotiable if you want fast iteration.
* Lean on SBCL’s introspection (`trace`, inspector, disassembler) aggressively.

### Tier 6: Performance / systems glue (add when needed)

* **CFFI** only if you plan to reuse Emacs C primitives or call into system libs early.
* **Bordeaux-Threads** if you want portability, but if SBCL-only, you can start with `sb-thread`.
* **lparallel** only if you have a real parallel workload (likely later).

---

## 3) Architectural choices to keep development fast *and* performance high

### A. Represent Elisp values mostly with CL primitives + a few structs

* Cons: use native cons.
* Integers: native fixnum/bignum.
* Strings/vectors: native arrays, but decide early how you model Emacs multibyte strings and text properties (you may wrap).
* Symbols: likely native CL symbols won’t work directly because Elisp has its own symbol namespace rules and obarray semantics. You’ll probably want an `el-symbol` struct:

  * name
  * value cell
  * function cell
  * plist
  * package/obarray pointer
  * flags (special/constant/keyword-like)

This is a spot where **struct + inline accessors** usually beats CLOS on hot paths.

### B. Environments: make them explicit and optimizable

You’ll need:

* Dynamic binding (specials) semantics
* Lexical environment for compiled code paths

Common approach:

* Lexical env: persistent mapping (alist or hash-table) while compiling; compiled output becomes CL `let`/`lambda` with decls.
* Dynamic env: explicit stack of bindings or leverage CL specials carefully (but you must not conflate CL’s global special vars with Elisp’s symbol-value cells).

### C. Macroexpansion pipeline: keep it deterministic and inspectable

You want:

* An Elisp macroexpander that returns Elisp AST (or CL forms tagged)
* A compiler lowering pass from Elisp AST → CL forms
* A final “emit CL” pass that inserts `(declare (optimize ...))`, type declarations, inline expansions, etc.

This is where having:

* Source locations (Eclector/CST)
* Pattern matching (Trivia)
* Debug printer for AST nodes
  pays off massively.

### D. Your `(el … (cl …) …)` bridging idea: treat it as two explicit phases

A robust pattern is:

1. `(el ...)` produces an **Elisp AST** (or annotated CL data representing Elisp).
2. A compiler pass lowers AST into CL.

For escape hatches:

* `(cl ...)` nodes become “verbatim CL” in the AST.
* Conversely, you might want a `(el* ...)` escape inside CL macros for convenience.

This prevents “accidental evaluation” issues and makes debugging macroexpansion sane.

### E. Start with interpret-first, compile-next (but design for compilation)

Even if the end goal is speed, the fastest path is:

* A small evaluator for correctness and test oracles
* A compiler to CL for performance once semantics stabilize

If you do this, invest early in:

* A canonical AST format
* A test suite that runs both interpreter and compiler backends on the same inputs

---

## 4) Dependency policy that won’t bite you later

Adopt a rule like:

* **Core runtime** (value representation, evaluator, compiler, basic libs): minimal deps (CL + maybe Alexandria).
* **Tooling layer** (reader, CST, debugging, testing): richer deps allowed (named-readtables, eclector, trivia, fiveam/parachute, slynk).
* **Optional integrations** (CFFI, concurrency libs): gated modules.

This keeps maintenance manageable and makes it easier to swap pieces.

---

## 5) A practical “starter stack” I would choose

If the goal is speed of development + good debugging without overcommitting:

**Core:**

* SBCL
* ASDF/UIOP
* Alexandria

**Syntax/AST:**

* named-readtables
* (optional but recommended) eclector

**Transforms:**

* (optional) trivia

**Testing:**

* fiveam *or* parachute (one)

**REPL/dev:**

* SLY + slynk (or SLIME + swank)

Everything else: add only when a concrete need shows up.

---

## 6) Early milestones for design planning (to de-risk fast)

1. Define the Elisp AST and printing/debug format.
2. Implement `(el ...)` reader/macro front-end that yields AST with source locations.
3. Implement a minimal evaluator for:

   * symbol-value/function cells
   * `let`, `setq`, `lambda`, `defun`, `if`, `progn`
   * basic function call / apply
4. Implement compiler lowering AST → CL and run through `compile` on SBCL.
5. Build compatibility tests that run interpreter vs compiled output on the same forms.

This sequence validates your DSL/escape design before you sink time into “full Emacs-ness” (buffers, markers, redisplay, etc.).

---

If you want a sharper recommendation on CLOS usage: reserve it for **buffers/markers/windows**, printing/introspection, and backend protocols; keep **symbol cells, cons/string/vector operations, evaluator dispatch** non-CLOS (structs + typecase + inline). That split tends to maximize both performance and developer velocity on SBCL.
</assistant>

<user>
I want where possible things to just be common lisp effectively so elisp constructs where possible are just CL aka host constructs or CL macros. We could allow some deviation from original elisp where we can prove that changes to existing elisp packages and code are simple and can be largely mechanical, like grep / replace. In that spirit how much does read syntax of elisp differ from CL. If we just went with CL would parching elisp be just a find and replace? Also dynamic scope is never used these days. How important that we keep it exactly like elisp and the default? All modern elisp essentials defaults to lexical scope. So if controlled changes to elisp syntax and semantic, simple to address downstream, are in scope, how does that change our implementation options. Think of it like using this opportunity to fix what’s broken in elisp and bring it closer to its new host Common Lisp so long as downstream changes required are almost mechanical
</user>

<assistant>
## 1) Read syntax: how far is Elisp from CL?

If you restrict yourself to the “modern Emacs Lisp subset” used by most packages (GNU ELPA/MELPA-era), the read syntax is close enough that a large fraction of files will parse as Common Lisp **without a custom reader**, but “mostly” is not “mechanical find/replace.” The remaining differences cluster around a few high-impact edges.

### Differences that usually force a reader or preprocessing pass

1. **Character syntax**

* Elisp: `?a`, `?\C-a`, `?\M-a`, `?\N{LATIN SMALL LETTER A}` etc.
* CL: `#\a` and implementation-dependent named chars / escapes.
  Mechanical rewrite is possible but you need a real token-level transform (regex gets hairy with all escape variants).

2. **Vectors**

* Elisp: `[1 2 3]`
* CL: `#(1 2 3)`
  This one *is* largely mechanical and amenable to token rewrite.

3. **Booleans and nil**

* Elisp: `nil` is false and empty list; `t` is true.
* CL: `NIL` is false and empty list; `T` is true.
  This aligns well, but you must ensure symbols are in the right namespace/package and you don’t accidentally intern `nil` as a distinct symbol.

4. **Keywords**

* Elisp: `:foo` is a symbol whose name starts with `:`, not a package-qualified keyword in the CL sense.
* CL: `:foo` reads as `KEYWORD:FOO` and self-evaluates.
  This is a major semantic mismatch. You can either:

  * accept CL keywords as the new reality (and adjust Elisp code expectations), or
  * implement an Elisp reader mode where `:foo` becomes an Elisp symbol in your “el” package/obarray.
    If you go “pure CL reader,” existing Elisp that treats `:foo` like an ordinary symbol will break in subtle ways (plist keys are usually fine; symbol-value and eq-identity assumptions may differ).

5. **Number syntax**

* Elisp accepts some notations that differ from CL expectations (and CL has its own reader macros like `#b`, `#x`, ratios, complex, etc.). Most plain decimals are fine. Edge cases will exist.

6. **String escapes**

* Similar enough that most code survives, but there are differences in some escape sequences and how multibyte/unicode escapes are spelled/handled.

7. **Comments**

* Both have `;` line comments.
* Elisp also uses `#@NNN` (in some contexts), and Emacs has “cookie” conventions (`;;;###autoload`, file-local variables blocks) which aren’t reader-level but matter to tooling.

8. **`#'` / function quoting**

* Elisp uses `#'` too (via CL compatibility), so this is usually fine.

### Bottom line

* If you insist on **CL reader only**, you will need a **source-to-source rewrite step** (token-aware) for at least: vectors, character syntax, and likely keywords semantics.
* It can be “almost mechanical,” but not “grep/replace only” for real-world packages.

A good design pattern is: **use the CL reader**, but run a **pre-reader rewriter** (a small lexer) that translates just the few tokens you care about into CL equivalents, then feed into normal `read`. That keeps you in “mostly CL” territory without writing a full reader.

---

## 2) Semantics: dynamic scope, lexical scope, and how strict you need to be

### Reality check: “dynamic scope is never used”

Modern packages often enable lexical binding (`lexical-binding: t`) and rely on it. But dynamic scope is still used in three important ways:

1. **Special variables for configuration and temporary bindings**
   Even in lexical-binding files, Emacs Lisp still has “special” variables (conventionally `*foo*`-style in CL, but not necessarily in Elisp) that are dynamically bound with `let`. Many core variables behave dynamically in practice.

2. **Advice, hooks, and “current buffer / current window” style implicit context**
   Even if not literally variable binding, lots of APIs assume dynamically-scoped “ambient context.” In Emacs that ambient context is partly variables, partly global state with save/restore macros.

3. **Old code and user init**
   If your target includes loading existing init files and older libs, dynamic behavior matters.

### If you are willing to change defaults

You can choose: “lexical is the default; dynamic must be declared.” This is closer to CL and modern expectations. Concretely:

* Default `let` is lexical.
* Introduce a declaration or macro for dynamic binding, e.g. `(dlet ((var val) ...) ...)` or CL’s `(let ((var val)) (declare (special var)) ...)`.
* Provide compatibility: treat variables declared special (or on a whitelist of “defvar/defcustom”) as dynamically bound.

This is a plausible compromise that keeps:

* Most modern code working with minimal changes,
* A clear story for “dynamic when you mean it,”
* A more CL-like mental model.

### How much compatibility you lose

If you drop “dynamic-by-default” entirely, you will break:

* Code that relies on temporarily rebinding global vars without declaring them special.
* Some idioms around `let` + callbacks expecting dynamic capture.

But if your goal is “almost mechanical changes,” you can:

* Auto-specialize known global variables defined via `defvar/defcustom` during load/compile.
* Provide a migration tool that inserts `(declare (special ...))` or rewrites to `dlet`.

This makes the delta closer to mechanical.

---

## 3) How these choices change implementation options

If you allow controlled semantic/syntax changes toward CL, you get major simplifications:

### A. You can compile most Elisp directly into CL forms

* `defun`, `lambda`, `let`, `setq`, `cond`, `progn`, `and`, `or`, `catch`/`throw` map reasonably.
* Many “CL package” features already exist in Elisp (`cl-lib`), and you can lean into the CL host instead of emulating.

### B. You can treat “Elisp” as mostly a compatibility layer + library

Instead of fully reimplementing the Elisp evaluator, you can:

* Provide an `EL` package/namespace + symbol/value/function-cell model only where Emacs expects it.
* Map common forms to CL macros/functions.
* Gradually reimplement Emacs-specific primitives (buffers, markers, etc.) as host objects.

### C. You can use CL’s macro system as the macroexpander

If you accept some differences, you can compile Elisp macros into CL macros and run CL macroexpansion.

Caveat: Elisp macroexpansion semantics differ in places (e.g. symbol resolution, environment objects, `macroexpand-all` behavior). But if you own the ecosystem boundary, you can define “the new macro semantics” and provide shims.

### D. You can eliminate (or drastically reduce) “interpreter correctness burden”

If you commit to “CL as the language,” your runtime becomes:

* CL compiler for speed,
* compatibility shims for Emacs APIs,
* a loader that does syntax/semantic patching.

That is generally faster to build and easier to optimize on SBCL.

---

## 4) Practical migration story: what is actually “mechanical”?

If you aim for “mostly mechanical changes” for downstream Elisp:

### Likely mechanical rewrites

* `[ ... ]` → `#( ... )`
* `?x` / `?\C-x` → `#\x` / some canonical CL char representation (may require helper like `#.(el-char "...")` for complex cases)
* `defvar` / `defcustom` / `setq-default` → equivalents that also mark specials or define config vars
* Some `cl-lib` forms can be removed/rewritten to native CL

### Not purely mechanical (needs awareness)

* `:foo` keyword semantics (choose one: accept CL keywords, or rewrite/read differently)
* Packages/obarrays vs CL packages
* Symbol function/value cell differences (CL’s `symbol-value`/`symbol-function` exist but package/interning rules differ)
* Emacs string/buffer/text properties (big semantic surface; can’t be “mechanical”)

---

## 5) Suggested “CL-first Emacs Lisp” compatibility contract

If your guiding principle is “be CL unless it’s painful,” a coherent contract looks like:

1. **Reader is CL, plus a tiny prepass**

* Translate vectors and Elisp char tokens.
* Decide on `:foo` now:

  * Option A: accept CL keywords; migration tool rewrites any code that depends on `:foo` being ordinary.
  * Option B: treat `:foo` as EL symbol; requires readtable/CST hook.

2. **Lexical by default**

* `let` is lexical.
* Variables introduced by `defvar/defcustom` become special (dynamic) by default, matching CL practice.
* Provide `dlet` for explicit dynamic binding of non-specials, and a migration tool that rewrites ambiguous `let` forms when needed.

3. **Macroexpansion and compilation are CL**

* Encourage writing macros in CL directly.
* Allow an `(el ...)` quasiquote DSL only where needed; otherwise just write CL.

4. **Compatibility layer targets “real Emacs APIs,” not old elisp evaluator quirks**

* You invest in buffers, markers, redisplay hooks, subprocess, file notifications, etc.
* You do not invest heavily in supporting every historical scoping edge-case unless required.

---

## 6) High-leverage decision you should make early

Choose your stance on `:keywords`.

* If you accept CL keywords as-is, you are materially closer to “just CL,” and many plist uses still work fine.
* If you require Elisp keyword-as-normal-symbol semantics, you are committing to reader customization and more semantic emulation.

In practice, for “CL-first” goals, **accept CL keywords** and treat any incompatibilities as a migration target.

---

If you want, I can outline a concrete “porting linter/rewriter” plan (tokenizer rules + transformations) that enables “CL reader only,” and list the specific Elisp constructs that still require runtime compatibility rather than rewrite.
</assistant>

<user>
Your 3) How these choices change implementation options section is pretty close to what i am aiming for. Elisp is essentially a compat layer + library. So many elisp forms and objects are just those of CL. Re keywords, nil and t, vector syntax: elisp has no modules everything is global namespace, but that makes it easy for us - we just introduce “elisp” package so every “naked” keyword we encounter in el is elisp namespaced i.e. part of our elisp package. And in that package can’t we intro slight changes to reader syntax? Even use [] for vectors, though that’s also easy enough to just replace in a separate pre-pass. Having a package for elisp may also help us bridge semantics? CL also has dynamic variables we could map the two and do a lot more with macros. And yeah a lot of cl-lib and eieio would just be parts of CL and CLOS subset or something. How does that change our implementation options?
</user>

<assistant>
### What your “Elisp as compat layer + library” approach enables

It shifts the problem from “implement an Elisp runtime” to “provide an Emacs substrate (buffers, markers, commands, redisplay, etc.) while letting SBCL/CL do the language work.” Concretely:

* Most special forms become **CL special forms/macros** (`if`, `progn`, `let`, `lambda`, `unwind-protect`, `catch`/`throw`, `condition-case`→`handler-case`, etc.).
* Most “object system” becomes **CLOS** (EIEIO largely disappears or becomes thin adapters).
* `cl-lib` becomes mostly unnecessary (or re-exported aliases for compatibility).
* Your “compiler” is largely **a loader + expander** that translates the remaining Emacs-isms into CL.

This is a good trade if you accept controlled incompatibilities and provide mechanical migration.

---

## 1) The “Elisp package” idea: what it buys you and what it doesn’t

### What it buys

* A single namespace boundary: read/compile all Elisp into the `ELISP` package.
* You can expose a curated CL surface inside that package (shadow/rename where needed).
* You can implement Elisp globals as CL globals (special vars, functions), and use symbol properties via your own tables.

### What it does *not* buy automatically

* Elisp’s **symbol cell model** (value cell + function cell + plist + name) differs from CL in details. CL symbols do have value/function cells and plist, but:

  * Package/interning semantics differ.
  * You will likely want a controlled intern/obarray story rather than raw `intern` everywhere.
* Elisp’s expectation that “everything is in one global namespace” is not the same as CL package rules. A single `ELISP` package approximates it, but you’ll still need to manage imports/shadowing.

### Recommended stance

* Use `ELISP` as the “surface language package.”
* But do **not** rely on CL’s package system as your only “obarray.” Provide an `el-intern` layer, even if it maps 1:1 to `intern` initially, so you can change later without touching user code.

---

## 2) Reader options: how far can you push “slight changes” safely?

You can do this cleanly without a full custom reader by combining:

1. **Named readtables** (so ELISP-mode reading is opt-in and local)
2. A small set of **reader macros** for the few Elisp tokens you want (`[]`, `?x`)

### Using `[]` for vectors

Yes: define `[` as a dispatch that reads until `]` and returns a CL vector (`#(...)`) or directly allocates a vector. This is a small, contained extension.

### Handling `:keywords`

If you read everything in `ELISP` package, `:foo` is still read by CL as `KEYWORD:FOO` before package selection matters. If you want “naked keyword becomes ELISP::|:foo|” semantics, you must either:

* change how `:` is read (hard; it is core token syntax), or
* accept CL keywords and treat them as the new meaning of `:foo`, or
* introduce a different token convention (e.g. `&foo` or `#:foo`-like) and migrate mechanically.

Pragmatically, for your goal (“be CL”), the best option is: **embrace CL keywords** and treat this as a compat divergence. Plist keys and option markers map well to keywords anyway.

### `nil` and `t`

Trivial: just use CL `NIL` and `T`. Ensure `ELISP` package does not intern a distinct `nil` symbol (don’t shadow NIL/T).

---

## 3) Scoping and dynamic variables: mapping Elisp to CL in a CL-first design

This is where your approach simplifies things a lot.

### Default lexical

Make lexical default. That matches modern Elisp and CL.

### Dynamic variables

Use CL specials as the mechanism:

* `defvar`/`defcustom` expands to `defparameter`/`defvar`-equivalent plus `(declaim (special ...))`.
* Elisp `let` over a “special” becomes dynamic binding automatically in CL.

This gets you the “Elisp/CL dynamic bridge” with very little runtime work.

### The only remaining problem

Elisp historically lets you dynamically bind variables without prior declaration. If you don’t want that, your migration story is:

* when loading legacy code, auto-infer specials (heuristics), or
* require declaration and offer an auto-rewriter.

Given your “controlled changes allowed,” require declaration and provide tooling.

---

## 4) What becomes simpler (implementation options you now have)

### A. Drop an Elisp bytecode interpreter entirely (or delay it indefinitely)

If “Elisp” compiles to CL forms, you can run SBCL’s compiler and get good performance immediately.

* Your main tool becomes: `READ (ELISP-READTABLE) -> EXPAND -> COMPILE`.
* “Bytecode” only matters if you need Emacs byte-compiled `.elc` compatibility.

### B. Implement Elisp special forms as macros that lower to CL

Example categories:

* Control: `condition-case` → `handler-case` (with mapping of condition types)
* Binding: `let*` → `let*`
* Nonlocal exit: `catch`/`throw` → `catch`/`throw` (CL has these)
* `save-excursion`, `save-restriction` etc. become macros using `unwind-protect`.

### C. Make “function cell vs value cell” just CL’s native split

Elisp has separate function namespace (`fset`, `symbol-function`, etc.). CL already does.
You mainly need to provide:

* `fboundp`, `fmakunbound`, `funcall`, `apply` wrappers with Elisp names.

### D. EIEIO becomes CLOS

* `defclass`, `defmethod`, `slot-value`, `make-instance` are native.
* Keep thin adapters so existing EIEIO code ports mechanically (`defclass` forms may need keyword normalization).

### E. Hook/advice system becomes a library

Instead of “baked into evaluator,” implement:

* hook variables as lists of functions
* `run-hooks`, `add-hook`, `remove-hook` as library functions
* advice as function wrappers (CLOS generic functions can help)

### F. Errors/conditions become CL conditions

Define a mapping between Elisp error symbols and CL condition classes, then:

* `(signal 'error ...)` → `error` or `signal` with a condition instance
* `condition-case` becomes `handler-case` with mapping from Elisp error symbols

---

## 5) What still requires a real “Emacs substrate” (cannot be solved by “just CL”)

Even with this design, the hard parts are Emacs runtime concepts:

* buffers, point, markers, narrowing
* text properties / overlays
* interactive commands + minibuffer completion
* keymaps, input events
* processes, timers, sentinels/filters
* redisplay model

Your CL-first approach does not remove these, but it prevents the language runtime from becoming the bottleneck.

---

## 6) A concrete recommended configuration of choices

Given your stated goals, the cleanest option set is:

1. **Language**

* Elisp forms mostly map to CL.
* Keep an `ELISP` package as the surface namespace.
* Treat keywords as CL keywords (compat divergence).

2. **Reader**

* Use a named readtable for ELisp.
* Add only:

  * `[` `]` vector syntax
  * `?` character syntax (translate to CL chars/integers as you decide)
* Everything else: standard CL reader.

3. **Scope**

* Lexical default.
* `defvar`/`defcustom` create specials; dynamic binding only for specials.
* Provide migration tooling for legacy dynamic-binding code.

4. **OO**

* CLOS is the object system. EIEIO becomes wrappers/aliases.

5. **Compilation**

* Compile to CL and let SBCL optimize.
* No bytecode compatibility initially.

---

## 7) Key risk to surface now

The biggest semantic mismatch you cannot “package away” is **Elisp symbols and intern/obarray behavior** versus CL packages, especially once you load lots of third-party code that assumes specific symbol identity rules.

The mitigation is simple and compatible with your approach:

* Define `el-intern`, `el-symbol-name`, `el-symbol-plist`, etc. as your API, even if the first implementation uses CL symbols directly.
* Keep the option to swap representation later (e.g., custom `el-symbol` struct) without rewriting everything.

---

If you want the next planning step: define an explicit “compat profile” document (what you intentionally diverge on: keywords, dynamic-by-default, `.elc`, etc.) and then design the ELisp readtable + macro lowering rules around that profile. That locks the surface area early and prevents later churn.
</assistant>

<user>
Let's continue conversation here.

I think my elisp as embedded but essentially compat + library idea, where much
of elisp just uses Common Lisp's (its host) facilities, is the right approach
and most concerns can be addressed e.g. by introducing a dedicated "elisp"
package.

We can also diverge from original elisp where we can guarantee that most fixes
to existing elisp will be mechanical (find/replace) with occasional breakage
we can fix. We're basically dragging elisp towards its host Common Lisp in our
case.

I want us to arrive at a more clear plan how CL fits in and replaces elisp
first before attempting to tackle remaining code in C. You brought up emacs
specific structures like buffers, keymaps etc but those are in C. Our first
goal is elisp "engine" and plugging our implementation in command loop, not
replacing all of C core. Luckily SBCL ffi story is decent, so maybe we can get
away with that in some parts.

Bigger story to discuss is how we introduce Common Lisp, since C remains. Is
it C first and it potentially call our Elisp implementation, or it is Common
Lisp first and we call into C and it can call us back. Extension vs embedding
story? But for now focus is porting elisp to common lisp host, that includes
replacing any C side explicit defuns and such cause lots of elisp is actually
defined in C - aka builtin functions.

I want us to have a discussion and brainstorming here and come up with a good
solid plan ahead.
</user>

<assistant>
We have two viable integration “forks” for introducing SBCL while C remains:

- **Option A (“emacl”, gradual / safer):** C hosts the process, keeps
  `Lisp_Object` + Emacs GC, embeds SBCL, and swaps the Lisp engine
  incrementally via existing `Ffuncall`/`Feval` chokepoints.
  See `plans/emacl.md`.

- **Option B (“clemacs”, ambitious):** SBCL hosts the process, CL values + SBCL
  GC become canonical, and the Emacs C code becomes a substrate library behind
  a handle-based API (requiring larger early C refactors).
  See `plans/clemacs.md`.
</assistant>
