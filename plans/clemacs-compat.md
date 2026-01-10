# clemacs compatibility report (living)

This is a living report for the SBCL-hosted clemacs bring-up (Option B1).
It records what is currently supported, what is intentionally different from
upstream Emacs Lisp, and how we expect migration to work.

## Current stance

- clemacs is a **CL-hosted dialect** that aims to run a useful subset of Emacs
  Lisp with mechanical migration where needed.
- CL is the host language and runtime; C exists only as a substrate dylib.
- When in doubt, prefer **explicit, documentable semantics** over historical
  quirks, but keep the surface close enough that porting is straightforward.

## Breadcrumbs (required)

Bring-up work creates lots of one-off “discoveries” that a future ELisp→CL
compiler/codegen pass will need. To keep this from rotting:

- Any time we implement or intentionally diverge on a semantic edge case,
  add a microtest to `clemacs/contract/semantics.microtests.sexp`.
- If a microtest is intentionally not Emacs-faithful, document the why as a
  dated entry in “Semantic decisions (dated)” below.
- Keep known failures explicit and dated in `clemacs/contract/*known-fail*`.

## Supported today (2026-01-05)

Reader / syntax
- `[]` vectors read as CL vectors.
- `?x` reads as an integer character code, including modifier forms like
  `?\C-\M-a`.
- String literals with text properties: `#("foo" 0 3 (a b))`.

Compatibility shims (ELISP package)
- Value + function cells (so `fset`/`symbol-function` can store non-CL-callables).
- Enough of `pcase`/backquote for early bootstrap + upstream ERT bring-up.
- `string-to-unibyte` / `string-to-multibyte` (incremental unibyte split).
- Minimal match-data/regexp plumbing used by early startup and ERT.

Runtime
- A minimal TTY loop exists (`clemacs:tty-main`) with:
  - insert/backspace, cursor motion (horizontal + vertical),
  - save/quit chords: `C-x C-s`, `C-x C-c` (legacy `C-s` / `C-q` remain).

## Known differences / missing pieces

- This is not a full Emacs Lisp implementation:
  - most of the shipped `lisp/` tree is not yet loaded in clemacs at startup
    (see `clemacs/contract/startup.*.files`),
  - upstream ERT is partially enabled (see `clemacs/contract/ert-upstream.tests`),
  - Emacs bytecode (`.elc`) compatibility is intentionally not a priority.
- Data model is CL-native; there is no `Lisp_Object` identity to preserve.

## Semantic decisions (dated)

- 2026-01-05: Incremental unibyte split for strings
  - Decision: treat CL strings as “multibyte”, introduce a distinct unibyte
    representation, and implement only the conversions/printers needed for
    early startup and ERT.
  - Rationale: preserves “run shipped ELisp unchanged” goals while keeping the
    implementation incremental (vs reimplementing Emacs strings up-front).
  - Test breadcrumbs: `clemacs/contract/semantics.microtests.sexp` (string cases).

- 2026-01-05: SBCL-backed backtrace subset for upstream ERT
  - Decision: implement `backtrace-get-frames` by capturing the host SBCL call
    stack and converting frames into a simple “(FUN . ARGS)” list; implement
    `backtrace-to-string` to render those frames in an Emacs-ish way.
    - Implementation note: `backtrace-get-frames` may synthesize an `ert-fail`
      frame from the corresponding `signal` frame, since SBCL can omit tail-call
      frames; it also drops most frame args to avoid huge/cyclic prints.
  - Rationale: upstream `ert-test-run-tests-batch-expensive` expects the batch
    backtrace output to include an `ert-fail(...)` frame with arguments.
  - Test breadcrumbs: `clemacs/contract/semantics.microtests.sexp` (backtrace-to-string).

- 2026-01-05: Defer full `oclosure`/`nadvice` bring-up (advice system)
  - Decision: load only the early portion of `lisp/emacs-lisp/oclosure.el`
    (enough to parse/define its type stubs), and temporarily skip
    `lisp/emacs-lisp/nadvice.el` in clemacs startup manifests.
  - Rationale: upstream `oclosure.el` assumes Emacs's closure/bytecode
    substrate (`closurep`, `make-closure`, `make-interpreted-closure`,
    `byte-code-function-p`, and the interpreted-closure vector layout). Those
    are not modeled in clemacs yet, so enabling `nadvice.el` would force an
    early detour into “Emacs closure emulation” rather than the CL-first
    runtime we ultimately want.
  - Breadcrumbs:
    - Skip entry: `clemacs/contract/lisp.allowed-skip.files`.
    - Checkpoints: `clemacs/contract/startup.*.files` (`oclosure.el` form limit).

- 2026-01-06: Port `oclosure.el` as funcallable CLOS objects (SBCL-only)
  - Decision: replace the early-load `oclosure.el` prefix with a clemacs-local
    port that models the bring-up-needed oclosure types (`accessor` and
    `cconv--interactive-helper`) as SBCL funcallable standard objects.
  - Rationale: clemacs currently maps ELisp `cl-defmethod` to host CLOS
    dispatch, so specializers need real CLOS classes; this approach unblocks
    `lisp/simple.el` bring-up without reintroducing Emacs bytecode/closure
    vector emulation.
  - Breadcrumbs:
    - Port: `clemacs/ported/lisp/emacs-lisp/oclosure.el`
    - Startup checkpoints: `clemacs/contract/startup.*.files` (`oclosure.el`)

- 2026-01-07: `cl-defgeneric` overwrites bring-up placeholder functions
  - Decision: when `cl-defgeneric` defines a generic function and the symbol
    already has a non-generic function definition, clemacs drops the existing
    fdefinition so the generic can take over.
  - Rationale: during bring-up we sometimes provide small, eager stubs (e.g.
    `seq-filter`) to keep smoke/microtests working before the full upstream
    file is loaded; SBCL rejects `defgeneric` when a non-generic fdefinition
    already exists.

- 2026-01-08: Scope internationalization to Unicode/UTF-8
  - Decision: treat non-UTF-8 legacy encodings and LEIM input-method catalogs
    as out of scope during bring-up; focus on “UTF-8 text in buffers + file
    I/O” as the baseline.
  - Rationale: simplifies early loader + coding-system surface area while we
    converge on an interactive TTY editor core.
  - Breadcrumbs:
    - Skip entry: `clemacs/contract/lisp.allowed-skip.files` (`lisp/leim/leim-list.el`)

- 2026-01-09: `completing-read` returns DEF in batch mode
  - Decision: when `noninteractive` is non-nil, clemacs `completing-read`
    returns the default (DEF) when provided (and errors when REQUIRE-MATCH is
    set and DEF is missing), rather than trying to read from stdin.
  - Rationale: clemacs contract gates run in noninteractive mode; attempting to
    read from stdin can block or EOF. Returning DEF unblocks many callers while
    we bring up the real minibuffer/completion pipeline.
  - Test breadcrumbs: `clemacs/contract/semantics.microtests.sexp` (`completing-read-noninteractive-default`).

- 2026-01-09: Minibuffer contents are tracked as last prompt input (TTY)
  - Superseded (2026-01-10): we now model the minibuffer as an editable buffer
    (`*Minibuf-0*`) with a prompt boundary.
  - Original rationale: unblock early callers that inspect/clear minibuffer text
    (e.g. file-name shadowing), without pretending we have full minibuffer UI.

- 2026-01-10: Minibuffer is modeled as an editable `*Minibuf-0*` buffer (TTY)
  - Decision: in TTY bring-up, `read-from-minibuffer` uses a real buffer
    (`*Minibuf-0*`) containing PROMPT followed by editable input, with
    prompt-safe editing primitives and a local minibuffer keymap.
  - Rationale: enables practical interactive workflows (`M-x`, completion,
    history navigation) and keeps behavior close to Emacs while we iterate.
  - Test breadcrumbs: `clemacs/contract/semantics.microtests.sexp` (minibuffer
    prompt-safety + history microtests).

- 2026-01-10: `key-parse` represents Meta as an ESC-prefix sequence (TTY)
  - Decision: `key-parse`/`read-kbd-macro` treat `M-` as an ESC-prefix key
    sequence (e.g. `M-p` → `[27 112]`) rather than Emacs's Meta-bit encoding.
  - Rationale: clemacs TTY currently models Meta input and shipped prefix maps
    via `esc-map` / ESC-prefixed event streams, so this aligns `kbd` parsing
    with actual runtime key dispatch.
  - Test breadcrumbs:
    - `clemacs/contract/semantics.microtests.sexp` (`keymaps-key-parse-m-p-esc-prefix`)

- 2026-01-10: Reinstall clemacs `command-execute` after startup (TTY)
  - Decision: for the clemacs TTY loop, reinstall `clemacs-command-execute` as
    `command-execute` after loading the startup manifest.
  - Rationale: upstream `lisp/` can redefine `command-execute` in ways that
    assume Emacs' C command loop; clemacs needs stable updates to
    `last-command`/`this-command` so key-repeat and minibuffer-driven flows
    behave predictably (notably `C-s` repeat and `M-%` query-replace).
  - Test breadcrumbs:
    - `clemacs/contract/semantics.microtests.sexp` (`command-execute-updates-last-command`; `:emacs nil` since programmatic `command-execute` doesn't update these vars in Emacs)
    - `clemacs:test:tty` (PTY-driven TTY edit/save/search/replace loop)

- 2026-01-10: Minimal multi-window model (TTY; window list only)
  - Decision: clemacs implements a minimal window surface (`split-window`,
    `other-window`, `delete-window`, `delete-other-windows`, `display-buffer`)
    as a simple list of live windows, without modeling Emacs' window tree or
    layout/size constraints yet.
  - Rationale: unblocks common help/minibuffer workflows that expect a second
    window and basic window selection, without pulling in the full window
    manager during bring-up.
  - Test breadcrumbs: `clemacs/contract/semantics.microtests.sexp`
    (`windows-split-other-delete-basic`).

- 2026-01-10: Minimal isearch/query-replace slice (TTY; non-incremental)
  - Decision: clemacs provides `isearch-forward`/`isearch-backward` as simple
    minibuffer-prompted literal searches (not full incremental isearch yet).
    `query-replace` is a literal-string loop; in `noninteractive` mode it
    replaces all occurrences without prompting.
  - Rationale: provides core "real editing" workflows early (search + replace)
    while we iterate on the full incremental isearch UI/state machine later.
  - Test breadcrumbs: `clemacs/contract/semantics.microtests.sexp`
    (`query-replace-noninteractive-replaces-all`).

## Compiler/codegen notes (for later)

These are constraints the eventual ELisp→CL compiler must preserve; if a new
compat shim changes any of these, add a microtest and update this section.

- Don’t compile “to Emacs bytecode”: compile (expanded) ELisp to CL forms that
  call the ELisp runtime helpers, then let SBCL compile.
- Preserve ELisp function/value cell behavior (`fset` can store non-callables;
  `funcall` resolves symbols/lambdas via ELisp rules).
- Preserve local function bindings for `#'` / `(function F)` inside `labels` /
  `flet` / `cl-labels`-style constructs: a symbol designator alone can’t refer
  to a local function in host CL, so codegen must emit a host function object
  when a local function binding exists (see microtest:
  `clemacs/contract/semantics.microtests.sexp`).
- `macroexpand-all` must treat ELisp special operators as non-macros even when
  bootstrapped as CL macros (notably `setq` and `function`), otherwise deep
  macroexpansion can rewrite code in the wrong host lexical environment (ERT
  nested `should` is a canary here).
- Preserve dynamic binding + special variable behavior for `defvar`/`defcustom`
  and non-local exits (`catch`/`throw`, `condition-case`).
- Preserve string byte/char semantics (unibyte vs multibyte) and match-data.
- Preserve char-table objects (notably syntax tables): `make-syntax-table` builds
  a char-table with inheritance, and `modify-syntax-entry` stores raw syntax
  descriptors as conses `(CODE+FLAGS . MATCH)` where the low 8 bits are the
  syntax class and the prefix flag is bit 20 (see microtest:
  `clemacs/contract/semantics.microtests.sexp`).
- Keep function names/arguments visible to `backtrace-get-frames` so ERT batch
  output can include `ert-fail(...)` frames.
- (2026-01-05) Reader/codegen must preserve ELisp symbol tokens like `:` and `|`
  as ordinary symbols (rx DSL uses `(: ...)` and `(| ...)`). Today we implement
  this via a loader sanitizer for standalone `:` plus an ELisp readtable tweak
  for `|` (see microtests `reader-bare-colon-symbol` and
  `reader-bare-pipe-symbol` in `clemacs/contract/semantics.microtests.sexp`).

## Contract gate (clemacs)

The clemacs contract is separate from upstream Emacs' `test/contract/*`.

- Smoke gate: `mise run clemacs:test:contract -- --level smoke`
- Today this runs:
  - `clemacs:test:smoke` (FiveAM)
  - `clemacs:test:tty` (PTY-driven TTY edit/save/quit)

## ERT strategy (planned)

Goal: run an expanding subset of upstream ERT tests under clemacs, with an
explicit skip list for unsupported features.

Proposed steps:
- Implement enough of `ert.el` (or load it) to run `ert-run-tests-batch`.
- Start with a tiny curated set of upstream tests that require only:
  - reader + basic special forms + lists/vectors/strings,
  - plists + a handful of predicates.
- Add a compatibility report section per test file as it is enabled.
