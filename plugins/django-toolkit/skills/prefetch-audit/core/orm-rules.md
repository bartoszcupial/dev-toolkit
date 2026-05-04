# Django ORM rules

Domain knowledge specific to this audit. Linked from `SKILL.md`.

## Cache mechanic in one paragraph

`prefetch_related` runs a separate query for the related rows and attaches them as a Python list on the parent object. Once attached, `.all()` on the relation returns that cached list with no DB hit. **Any chained method that produces a different SQL query** — `filter`, `exclude`, `order_by`, `count`, `exists`, `values`, `annotate`, `aggregate`, `distinct`, `only`, `defer`, `iterator`, `first`, `last`, etc. — invalidates the cache and re-queries. Authoritative reference: https://docs.djangoproject.com/en/stable/ref/models/querysets/#prefetch-related (use the version-pinned URL matching the detected `DJANGO=` line when citing in a finding).

## Per-parent vs single-shot

The same cache bypass is CRITICAL or MEDIUM depending on context.

- **Per-parent** — the enclosing function runs once per object during list serialization. Resolvers, serializer methods, model `@property` accessed during list response shapes, admin `list_display` callables, signal handlers fired per row, Celery tasks iterating a queryset, `for obj in queryset:` loop bodies.
- **Single-shot** — the enclosing function runs once per request. Detail views (`retrieve`), one-off mutations, management commands processing a single record.

When unsure, **trace callers** before classifying. A function that *looks* single-shot but is also called from a list action via a mixin, or from a Celery task iterating, is per-parent in those callers and the bug is CRITICAL. The classification is per *callsite chain*, not per function name.

## Severity

- **CRITICAL** — per-parent callsite chains a query-firing verb on a related manager. N+1 in production.
- **MEDIUM** — single-shot callsite bypasses an *existing* prefetch (one wasted query). Requires a concrete `path:LINE` for the upstream prefetch site. No prefetch site → no MEDIUM.
- **Drop entirely (not a finding)** — single-shot callsite, no upstream prefetch, doing `.count()` / `.exists()` / `.aggregate()` on a relation. Idiomatic Django; not a bug.

If per-parent vs single-shot is genuinely ambiguous after tracing callers, default to CRITICAL and note the ambiguity in the `Problem` line.

## Django version notes

| Detected version | Note |
|---|---|
| Anything matching `EOL — upgrade strongly recommended` | Add a `Notes` line: out-of-support, recommend upgrade. Apply the audit anyway. |
| `4.2.x` LTS | Stable. No prefetch-behavior caveats. |
| `5.0.x` / `5.1.x` | `Prefetch` chaining tightened in 5.1; cite release notes if a finding involves nested `Prefetch` instances. |
| `5.2.x` / `6.x` | Verify against release notes via `WebFetch` when a finding involves nested `Prefetch` queryset filters. |
| `(declared, may be unpinned)` | Version came from `pyproject.toml` — actual installed version may differ. **Skip version-gated rules.** Add a `Notes` line recommending a lock file. |
| `unknown` | No lock file found. Skip version-gated rules entirely. Add a `Notes` line. |

## Helper-function pattern (the gotcha)

When a per-parent callsite calls a helper function that returns a queryset — even one with a correct internal `prefetch_related` — **the helper itself runs per parent**. The internal prefetch optimizes within that one call, but the helper is still invoked N times.

```python
def get_active_orders(user):
    return Order.objects.with_items().filter(user=user)  # internal prefetch is fine

@strawberry_django.field
def my_orders(self) -> list[OrderType]:
    return get_active_orders(self.user)  # ← helper runs per parent → N+1
```

Trace function calls inside per-parent callsites. If the called function performs ORM operations or returns a queryset, the entire helper-call is per-parent regardless of internal optimization. Fix: lift the helper into the upstream queryset construction (`get_queryset`, `Schema.from_orm`, etc.) so it runs once for the whole list.

## Custom manager methods can hide ORM verbs

A chain like `parent.children.with_active().order_by('id')` *looks* like a method call, but `with_active()` may be a custom manager method that internally does `.filter(is_active=True)`. The cache bypass is real but invisible at the callsite. **Before classifying any chain that uses a non-standard method name on a related manager, open the manager / queryset definition** and confirm what the method actually does. If it returns a fresh queryset (which custom manager methods almost always do), the cache is bypassed regardless of the trailing verb.

## Anti-patterns to flag (beyond the verb chain)

- **`Prefetch(queryset=...)` whose inner queryset omits `select_related(...)`** for an FK the consumer reads → nested FK N+1.
- **`Prefetch(..., to_attr='x')` defined upstream but never consumed** by the resolver → original relation re-queried.
- **`.iterator()` on a queryset that had `prefetch_related` applied** → silently discards the cache.
- **List comprehension with an ORM call in the predicate** (`[c for c in parent.children.all() if SomeModel.objects.filter(...).exists()]`) → turns N+1 into N×M. Plain attribute reads are fine; ORM calls are not.
- **`.select_related(...)` inside a per-parent resolver / serializer method** → strong signal of N+1. If the upstream queryset is properly prefetched, the resolver should consume the cache (`.all()`, `to_attr`), not re-fetch with `select_related`. Treat its presence as a finding even before checking the trailing verb.
