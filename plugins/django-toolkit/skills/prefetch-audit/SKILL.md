---
description: Audit Django code for N+1 prefetch_related bugs. Strawberry-django, DRF, and Django Ninja aware. Use before merging ORM / resolver / serializer changes.
when_to_use: "Before merging ORM / resolver / serializer changes, after adding prefetch_related(), or when investigating N+1 symptoms."
argument-hint: "[path]"
disable-model-invocation: true
allowed-tools: Read Grep Glob WebFetch Bash(git diff:*) Bash(git status:*)
context: fork
agent: Explore
---

# Prefetch Audit

Find N+1 query bugs in Django code: per-parent callsites that fire a DB query per parent because they bypass or miss a `prefetch_related` cache.

## Environment detection

Detect the stack before auditing. Use your tools — don't shell out to a script. Combine signals across these three sources, in order:

1. **Read CLAUDE.md** at the project root and any nested `CLAUDE.md` inside the audit target's parent directories. If it names the Django version, API frameworks, or optimizer config, treat it as authoritative.

2. **Read the closest manifest.** Walk up from the audit target until you find one of (preferred order): `uv.lock`, `poetry.lock`, `Pipfile.lock`, `requirements*.txt`, `pyproject.toml`. Extract the Django version and any of these covered frameworks: `strawberry-graphql-django`, `djangorestframework`, `django-ninja`. A version sourced only from `pyproject.toml` is potentially unpinned — mark it `(declared, may be unpinned)`.

3. **Cross-validate via code grep.** `Grep` the audit scope for framework signals: `import strawberry_django` / `@strawberry_django\.`, `from rest_framework`, `from ninja`. Detection result combines manifest, code, and CLAUDE.md; record disagreement (declared but unused, or used but undeclared) in `Notes`.

**Hard gate — overlay loading is mandatory on code signal.** If `Grep` of the audit target returns *any* of the patterns below, you **must** load the corresponding overlay before writing any Finding. A missing manifest entry does not override code presence. Code signal is sufficient and binding.

| Code signal | Overlay you must load |
|---|---|
| `@strawberry_django\.` or `import strawberry_django` | [frameworks/strawberry-django.md](frameworks/strawberry-django.md) |
| `from rest_framework` | [frameworks/drf.md](frameworks/drf.md) |
| `from ninja` | [frameworks/ninja.md](frameworks/ninja.md) |

Apply Django version notes from [core/orm-rules.md](core/orm-rules.md) only when the version is concrete (not `unknown` or `(declared, may be unpinned)`).

If no overlay's code signal matches, audit as plain Django (admin, signals, Celery, model `@property`, loops). Don't load framework files you don't need.

## Target

Audit **$ARGUMENTS**.

- Empty → audit `git diff HEAD -- '*.py'`.
- File path → audit that file.
- Directory path → recurse `*.py`, skipping `migrations/`, `__pycache__/`, `.venv/`, `node_modules/`, `tests/fixtures/`. Cap at 200 files; mention truncation in `Notes` if hit.

Use `Glob` to enumerate. Don't shell out to `find`.

## What you're looking for

Two related bug shapes, same root cause:

1. **Cache bypass** — upstream code applied `prefetch_related(...)`; downstream code chains an ORM verb on the related manager (`obj.children.filter(...)`, `obj.children.count()`, `obj.children.order_by(...)`, etc.). The cache is invalidated; one DB query per parent.
2. **Missing prefetch** — no upstream `prefetch_related` exists; per-parent code touches a relation. One DB query per parent regardless.

The fix is the same in both cases: ensure the cache exists upstream *and* is consumed by the downstream resolver. See [core/orm-rules.md](core/orm-rules.md) for the underlying mechanic, severity rules, and the false-positive guard.

## Investigation method

You're not running a regex linter. You're a senior Django dev reading code with a specific lens. Apply judgment.

1. **Read with the call graph in mind.** For each Python file in scope, identify the per-parent callsites — methods that the framework invokes once per object during list serialization, model `@property` accessed on list pages, admin `list_display` callables, signal handlers, Celery task bodies, `for obj in queryset:` loops. The framework overlay tells you which method names matter for the detected stack.

2. **Trace into helpers.** Per-parent code often calls a helper that returns a queryset. Even if the helper does a perfect `prefetch_related` internally, **the helper itself runs per parent** — so the prefetch optimizes within each call but doesn't help across calls. Read the helper. If it touches the ORM and is called with parent-derived arguments inside a per-parent callsite, the entire call is per-parent. See the "Helper-function pattern" section in [core/orm-rules.md](core/orm-rules.md) for the canonical example.

3. **Run the overlay's `Prerequisites` rule for each suspicious chain.** Each loaded overlay declares what to grep for and how to interpret the result. The rule does two jobs: (a) it anchors the prefetch site (`path:LINE`) on the finding; (b) where the framework offers a native shortcut, it tells you whether the shortcut is currently available (e.g. is strawberry's `DjangoOptimizerExtension` registered?). If the prerequisite isn't met, follow the overlay's fallback before writing the Fix section. For plain-Django findings (no overlay), look in the obvious places — `@model_property` on the model, custom managers wrapping `prefetch_related`, the `for` loop's queryset source — and record `path:LINE` or `Not prefetched (fix must add one)`.

4. **Classify per-parent vs single-shot by tracing callers.** A function that *looks* single-shot (a `retrieve` action, a helper named `get_one_thing`) may also be reachable from a list action via a mixin, from a Celery batch task, or from a serializer that's used on both detail and list views. Use `Grep` to search for callers before applying the false-positive guard. The classification is per *callsite chain*, not per function name.

5. **Apply severity rules.** CRITICAL / MEDIUM / drop — see [core/orm-rules.md](core/orm-rules.md). The single false positive to suppress: single-shot `.count()` / `.exists()` on a non-prefetched relation is idiomatic Django, drop entirely.

## Fix shapes

**For findings inside a framework overlay's scope**, follow that overlay's Fix structure. Two-option overlays (currently: strawberry-django) present `**Option A**` + `**Option B**`, each carrying a one-line `*Best fit for this finding:*` verdict that cites Pre-flight signals — see the per-finding format in the Output section. Single-option overlays (DRF, Ninja) present the canonical shape with one verdict line.

**For plain-Django findings (no overlay applies)**, two patterns cover almost every fix:

**SQL-filter shape** — push the filter into the prefetched queryset, materialize only matching rows:

```python
Parent.objects.prefetch_related(
    Prefetch(
        'children',
        queryset=Child.objects.select_related('category').filter(is_active=True),
        to_attr='active_children',
    )
)
# downstream consumes parent.active_children — plain list, no re-query
```

**Python-filter shape** — prefetch the whole relation, filter in a Python comprehension:

```python
Parent.objects.prefetch_related('children__category')
# downstream:
[c for c in parent.children.all() if c.is_active]
```

**Pattern B (Python-filter) validity rule:** the comprehension predicate must be a plain attribute read or a read of a pre-prefetched attribute. ORM calls in the predicate (`.filter()`, `.exists()`, `Model.objects.*`) turn N+1 into N×M and disqualify Pattern B for that finding — propose only the SQL-filter shape.

**Trade-off line** (use verbatim when both plain-Django shapes apply):

> Pick the SQL-filter shape if the relation can be large or you only need one subset. Pick the Python-filter shape if the relation is small and bounded or you need multiple subsets (partition once, one query total).

Other recurring fixes:

- `.count()` on a prefetched relation → `len(parent.children.all())` (uses the cache).
- `Prefetch` whose inner queryset omits `select_related` for an FK the consumer reads → add the inner `select_related`.
- `to_attr` defined upstream but not consumed → consume the `to_attr`, don't reach for the original relation.

## Doc grounding

When you emit a finding, cite the relevant authoritative doc on a `Reference:` line: Django ORM (https://docs.djangoproject.com/en/<version>/ref/models/querysets/), the framework overlay's doc URL, or both. Use `WebFetch` when uncertain about version-specific behavior. **Do not** cite memory files, CLAUDE.md, or any personal-context file — only framework docs, Django docs, or a reproducing `assertNumQueries` test.

## Output

Your **first emitted token is `#`**. Anything before — "Now let me…", "I'll start by…", "Let me analyze…", or any other narration — is a bug. Run all detection, grepping, and reading silently with your tools, then emit the structured output below in one shot.

Use this structure exactly.

---

### Pre-flight

Required block. Emit verbatim, one line each, before the Summary. The agent that skipped this block on the previous run is the failure mode this exists to prevent.

```
- Target: <path or "git diff HEAD -- '*.py'">
- Overlays loaded: <strawberry-django | drf | ninja | none>  (signals: <code: imports/decorators found in <files>> + <manifest: package found in <file>> | CLAUDE.md asserts)
- DjangoOptimizerExtension: <path:LINE registered with schema | imported but not registered | not found>   ← only if strawberry-django overlay loaded
- Queryset builder for target: <path:LINE | not located, fix must add one>
- Other consumers of that queryset builder: <list of paths or "none — dedicated to this view">
```

The verdict on each Fix option must cite at least one line from this block. No verdict without evidence.

### Summary

2–4 sentences: scope (files audited, target path), findings by severity, dominant pattern. State the detected Django version and frameworks. If clean, say so plainly.

### Findings

Omit if none. For each:

**[SEVERITY] `path/to/file.py:LINE` — short title**

- **Problem:** One sentence.
- **Current code:**
  ```python
  # 2–5 lines
  ```
- **Prefetch site:** `path:LINE` OR `Not prefetched (fix must add one)`.
- **Why it breaks:** One sentence tying to the rule.
- **Fix:** Use the structure for the loaded overlay (or plain Django if no overlay loaded):

  **Two-option overlay loaded** (currently: strawberry-django) — every Fix block **must** contain `**Option A**` and `**Option B**` subheadings, each followed by code, each followed by a one-line `*Best fit for this finding:*` verdict. Verdict format:

  ```
  **Option A — Framework-native (<short label>)**
  ```python
  <code>
  ```
  *Best fit for this finding:* <Yes — primary recommendation | No | Yes, with caveat>. <one-line reason citing a Pre-flight signal>

  **Option B — Upstream ORM prefetch**
  ```python
  <code>
  ```
  *Best fit for this finding:* <Yes — primary recommendation | No | Yes, with caveat>. <one-line reason citing a Pre-flight signal>
  ```

  Exactly one option per finding is labeled "Yes — primary recommendation." If a sub-option is invalidated (predicate disqualifies Python-filter; optimizer not registered), keep the header and state the disqualification on the verdict line — do not omit the option.

  **Single-option overlay loaded** (DRF, Ninja) — present the canonical shape with the verdict line: `*Best fit for this finding:* Yes — only valid placement is <path:LINE from Pre-flight>.`

  **No overlay loaded (plain Django)** — present SQL-filter and Python-filter shapes with verdict lines on each. The trade-off rules in [core/orm-rules.md](core/orm-rules.md) drive the verdict.
- **Reference:** doc URL + detected version (framework-specific findings) or Django docs URL (ORM-only findings).

Sort CRITICAL → MEDIUM, then by path.

### Recommended action plan

3–7 numbered items. Each names the file(s) and the specific change. Collapse findings that share a file *and* fix shape into one item (two sibling resolvers in the same module with the same `Prefetch` fix → one item). Fold upstream prerequisites into the same item as the resolver change — never mark them "optional."

### Notes

Use for:

- `DJANGO=unknown` → environment detection inconclusive; version-gated rules skipped.
- `(declared, may be unpinned)` → version came from `pyproject.toml`; install a lock file for accurate version-aware audit.
- EOL Django version → upgrade strongly recommended.
- Manifest/code disagreement (declared but unused, or used but undeclared) → call it out so the user can fix project state.
- Scan truncation, ambiguous classifications, frameworks detected outside the covered set.

Skip the section entirely if there's nothing to say.

---

## Constraints

- Review-only. No file modifications.
- Local-first investigation. Grep outward only to answer a specific question — don't crawl the project.
- Use `Grep` to locate suspect chains; don't read files cover-to-cover. Read the full relevant function, not the whole module.
- Always run the loaded overlay's `Prerequisites` rule and emit the Pre-flight block before writing a Fix — never skip ahead with a guess.
- For findings under a two-option overlay, present *both* options with verdict lines. Each verdict must cite a Pre-flight signal. Exactly one option is labeled "Yes — primary recommendation"; never omit an option because you've already picked a winner.
- The framework-native option is *not* the default winner. Apply the overlay's bidirectional evaluation rule: there are real cases where upstream ORM beats framework-native even when the framework is fully wired up (shared queryset builder, unconditional field selection, multiple subsets).
- The single false-positive guard: single-shot `.count()` / `.exists()` / `.aggregate()` on a non-prefetched relation = not a finding. Verify single-shot status by tracing callers first. Drop entirely if the guard applies — no MEDIUM, no "optional" hedge.
- MEDIUM requires a concrete `path:LINE` upstream prefetch site. No prefetch site → no MEDIUM.
- Total output ≤ 400 lines. One final output, no intermediate drafts, no preamble.
- Collapse findings that share a file + fix shape into one action-plan item.
