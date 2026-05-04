# Django Toolkit

Django-focused audits and base setup for Claude Code. Strawberry-django, DRF, and Django Ninja aware. Read-only — never modifies code.

## Features

- **Per-parent N+1 detection** — Flags `prefetch_related` cache bypasses and missing prefetches in resolvers, serializer methods, model `@property`, admin callables, signals, Celery tasks, and `for obj in queryset:` loops.
- **Multi-framework coverage** — Strawberry-django (`@strawberry_django.field`, `@model_property`, the `DjangoOptimizerExtension` selection-aware bypass trap), DRF (`SerializerMethodField`, `to_representation`, `ViewSet.get_queryset`, `setup_eager_loading`), and Django Ninja (`Schema.resolve_<field>`, route-handler queryset placement, `from_orm` timing).
- **Helper-function awareness** — Catches the common gap where a helper that internally uses `prefetch_related` is invoked per-parent inside a resolver — the helper still runs N times regardless of its internal optimization.
- **Environment detection** — Django + API-framework versions resolved by reading `CLAUDE.md`, the closest manifest (`uv.lock`, `poetry.lock`, `Pipfile.lock`, `requirements*.txt`, `pyproject.toml`), and cross-validating against actual `import` / decorator usage in the audit scope. Robust to monorepos, declared-but-unused deps, and unusual lockfile spellings.
- **Doc grounding** — Cites the framework's own optimizer/serializer guide on every framework-specific finding, pinned to the detected version.
- **Project-aware fix recommendations** — When a framework offers a native shortcut (e.g. strawberry-django's `DjangoOptimizerExtension`), the audit verifies the prerequisite is wired up, presents both the framework-native and upstream-ORM options, and recommends one based on observed project signals — instead of dumping a generic shape and leaving the developer to choose blind.

## Usage

```
/django-toolkit:prefetch-audit
```

Argument forms:

```
/django-toolkit:prefetch-audit                       # audits git diff HEAD -- '*.py'
/django-toolkit:prefetch-audit apps/orders/          # audits a directory
/django-toolkit:prefetch-audit apps/orders/types.py  # audits one file
```

## Workflow

1. **Detect environment** — Read `CLAUDE.md`, then the closest manifest, then `Grep` for framework imports/decorators in the audit scope. A framework counts as detected only when manifest *and* code agree (or `CLAUDE.md` asserts it). Disagreement is recorded in `Notes`.
2. **Identify target files** — Empty arg → diff; file → that file; directory → recurse `*.py` (skipping `migrations/`, `__pycache__/`, `.venv/`, fixtures; cap 200 files).
3. **Read with the call graph in mind** — Locate per-parent callsites by reading code semantically (not regex-only). Trace function calls into helpers; a helper called per-parent is per-parent regardless of its internal prefetch.
4. **Apply rules** — Cache mechanic + per-parent vs single-shot classification + false-positive guard with caller verification.
5. **Apply framework overlays** — Load only overlays for confirmed frameworks. Each overlay's `Prerequisites` rule runs to anchor the prefetch site and verify framework-native preconditions (e.g. `DjangoOptimizerExtension` registration for strawberry-django, `ViewSet.get_queryset` placement for DRF, route-handler placement for Ninja).
6. **Locate prefetch site** — Driven by the overlay's `Prerequisites` rule. For plain-Django findings: `@model_property` on the model, custom managers wrapping `prefetch_related`, the `for` loop's queryset source.
7. **Classify severity** — CRITICAL (per-parent) / MEDIUM (single-shot bypassing a confirmed prefetch) / drop (single-shot without prefetch — idiomatic Django).
8. **Emit findings** — Structured report: `Summary` → `Findings` → `Recommended action plan` → `Notes`. For findings with a framework-native shortcut, the `Fix` block presents Option A + Option B + a project-aware Recommendation.

## Severity Rules

| Severity | Trigger |
|----------|---------|
| CRITICAL | Per-parent callsite chains a query-firing verb on a related manager (N+1 in production). |
| MEDIUM | Single-shot callsite bypasses a confirmed prefetch (one wasted query). Requires a concrete `path:LINE` prefetch site. |

Single-shot `.count()` / `.exists()` on a non-prefetched relation is **not** a finding — idiomatic Django. The skill verifies single-shot status by tracing callers before applying this guard.

## Supported Frameworks

| Layer | Coverage |
|-------|----------|
| Django ORM (any version) | Cache mechanic, severity rules, version-aware notes |
| Universal callsites (admin, signals, Celery, `@property`, loops) | Framework-agnostic |
| Strawberry-django | `@strawberry_django.field`, `@model_property`, `DjangoOptimizerExtension` selection-aware bypass |
| Django REST Framework | `SerializerMethodField`, `to_representation`, `ViewSet.get_queryset`, `setup_eager_loading`, `source=` dotted paths |
| Django Ninja | `Schema.resolve_<field>`, route-handler queryset placement, `from_orm` timing, async wrapper interaction |

## Example Output

```
### Summary
Audited apps/orders/ — N Python files. Detected Django <version> with strawberry-graphql-django <version>.
Found <N> N+1 bugs: <count> CRITICAL in resolvers chaining ORM verbs on related managers,
<count> MEDIUM bypassing a confirmed prefetch.

### Findings

[CRITICAL] apps/orders/schema.py:LINE — active_line_items resolver chains filter on related manager

- Problem: Resolver runs once per Order and chains `.filter()` on `self.line_items`,
  bypassing any upstream prefetch and firing one query per parent.
- Current code:
  @strawberry_django.field()
  def active_line_items(self) -> list[LineItemType]:
      return self.line_items.filter(is_active=True)
- Prefetch site: Not prefetched (fix must add one).
- Why it breaks: Any chained ORM verb on a related manager invalidates the prefetch cache.
  Per-parent context = N+1.
- Fix:
  # Option A — Framework-native (field-level hint, requires DjangoOptimizerExtension):
  @strawberry_django.field(prefetch_related=[
      lambda info: Prefetch('line_items',
          queryset=LineItem.objects.select_related('product').filter(is_active=True),
          to_attr='active_line_items')])
  def active_line_items(self) -> list[LineItemType]:
      return self.active_line_items

  # Option B — Upstream ORM prefetch (in the queryset builder):
  Order.objects.prefetch_related(
      Prefetch('line_items',
          queryset=LineItem.objects.select_related('product').filter(is_active=True),
          to_attr='_active_line_items'))
  # resolver consumes the to_attr:
  return parent._active_line_items

  Recommendation: <one paragraph citing the project signals surfaced by the overlay's
  Prerequisites rule (e.g. whether DjangoOptimizerExtension is registered, where the
  queryset builder lives, who else consumes it) and selecting Option A or B accordingly>.
- Reference: https://strawberry.rocks/docs/django/guide/optimizer (strawberry-graphql-django <version>)

### Recommended action plan
1. <file:LINE> — <change>.

### Notes
(empty when nothing to report)
```
