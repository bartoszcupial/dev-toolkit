# Django Toolkit

Django-focused audits and base setup for Claude Code. Strawberry-django, DRF, and Django Ninja aware. Read-only — never modifies code.

## Features

- **Per-parent N+1 detection** — Flags `prefetch_related` cache bypasses and missing prefetches in resolvers, serializer methods, model `@property`, admin callables, signals, Celery tasks, and `for obj in queryset:` loops.
- **Multi-framework coverage** — Strawberry-django (`@strawberry_django.field`, `@model_property`, the `DjangoOptimizerExtension` selection-aware bypass trap), DRF (`SerializerMethodField`, `to_representation`, `ViewSet.get_queryset`, `setup_eager_loading`), and Django Ninja (`Schema.resolve_<field>`, route-handler queryset placement, `from_orm` timing).
- **Helper-function awareness** — Catches the common gap where a helper that internally uses `prefetch_related` is invoked per-parent inside a resolver — the helper still runs N times regardless of its internal optimization.
- **Environment auto-detection** — Django + API-framework versions resolved from lock files (`uv.lock`, `poetry.lock`, `Pipfile.lock`, `requirements*.txt`, `pyproject.toml`). Pure shell, no Python interpreter required, works in Docker-only setups.
- **Doc grounding** — Cites the framework's own optimizer/serializer guide on every framework-specific finding, pinned to the detected version.
- **Multi-shape fixes** — When multiple valid fix shapes exist, all are shown with a one-line trade-off; the developer picks.

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

1. **Detect environment** — A bundled shell script walks lock files for Django + API-framework versions and emits a structured block (`DJANGO=`, `FRAMEWORKS_INSTALLED=`, `LOCKFILE=`) injected at skill load.
2. **Identify target files** — Empty arg → diff; file → that file; directory → recurse `*.py` (skipping `migrations/`, `__pycache__/`, `.venv/`, fixtures; cap 200 files).
3. **Read with the call graph in mind** — Locate per-parent callsites by reading code semantically (not regex-only). Trace function calls into helpers; a helper called per-parent is per-parent regardless of its internal prefetch.
4. **Apply rules** — Cache mechanic + per-parent vs single-shot classification + false-positive guard with caller verification.
5. **Apply framework overlays** — Load only overlays for frameworks present in `FRAMEWORKS_INSTALLED`. Skip overlays for frameworks not in the project.
6. **Locate prefetch site** — Sibling `views.py` / `queries.py`, type's `get_queryset`, field-level hints, `@model_property` on the model, custom managers wrapping `prefetch_related`.
7. **Classify severity** — CRITICAL (per-parent) / MEDIUM (single-shot bypassing a confirmed prefetch) / drop (single-shot without prefetch — idiomatic Django).
8. **Emit findings** — Structured report: `Summary` → `Findings` → `Recommended action plan` → `Notes`.

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
Audited apps/review/ — 309 Python files. Detected Django 5.2.10 with strawberry-graphql-django 0.65.1
and djangorestframework 3.16.1. Found 3 N+1 bugs: 2 CRITICAL in Review resolvers chaining .filter()
on related managers, 1 MEDIUM in a resolver chaining .order_by() on a prefetched relation.

### Findings

[CRITICAL] apps/review/schema/nodes.py:40 — star_ratings resolver chains filter on related manager

- Problem: Resolver runs once per Review and chains `.select_related().filter()` on `parent.star_ratings`,
  bypassing any upstream prefetch and firing one query per parent.
- Current code:
  @strawberry_django.field()
  def star_ratings(self, parent: strawberry.Parent) -> list[RatingType]:
      return parent.star_ratings.select_related('question').filter(question__is_additional=False)
- Prefetch site: Not prefetched (fix must add one)
- Why it breaks: Any chained ORM verb on a related manager invalidates the prefetch cache. Per-parent
  context = N+1.
- Fix:
  # SQL-filter shape (callable Prefetch hint):
  @strawberry_django.field(prefetch_related=[
      lambda info: Prefetch('star_ratings',
          queryset=Rating.objects.select_related('question').filter(question__is_additional=False),
          to_attr='active_star_ratings')])
  def star_ratings(self) -> list[RatingType]:
      return self.active_star_ratings

  # Python-filter shape (string hint + comprehension):
  @strawberry_django.field(prefetch_related=['star_ratings__question'])
  def star_ratings(self) -> list[RatingType]:
      return [r for r in self.star_ratings.all() if not r.question.is_additional]

  Trade-off: Pick SQL-filter if the relation can be large or you only need one subset.
  Pick Python-filter if the relation is small and bounded or you need multiple subsets
  (partition once, one query total).
- Reference: https://strawberry.rocks/docs/django/guide/optimizer (strawberry-graphql-django 0.65.1)

### Recommended action plan
1. apps/review/schema/nodes.py:40, :44 — switch both star_ratings resolvers to the same fix shape.

### Notes
(empty when nothing to report)
```
