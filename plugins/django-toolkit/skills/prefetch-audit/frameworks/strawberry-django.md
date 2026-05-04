# Strawberry-django overlay

Apply when `strawberry-graphql-django` is confirmed in the environment-detection summary. Linked from `SKILL.md`.

## What's unique here

Strawberry-django's `DjangoOptimizerExtension` reads field-level `prefetch_related=` / `select_related=` hints and applies them **selection-aware**: it prefetches only what the GraphQL query asks for, and dedupes identical hints across sibling resolvers. This is the framework-native shortcut — but it only fires when the extension is registered with the schema (see Prerequisites).

**The trap:** the optimizer applies the hint only when the resolver **consumes the cache** via `.all()` or accesses a `to_attr`. If the resolver chains `.filter()` / `.exclude()` / `.order_by()` etc. on the related manager, the hint silently no-ops. The prefetch query still runs (wasted), and the resolver fires its own per-parent query on top.

```python
@strawberry_django.field(prefetch_related=['line_items'])
def active_line_items(self) -> list[LineItemType]:
    return self.line_items.filter(is_active=True)   # ← bypasses the hint, N+1
```

On a `@strawberry_django.type` the resolver receives `self` as the model instance; there is no second `parent` argument.

## Prerequisites

Before recommending the framework-native field-level hint (Option A), verify `DjangoOptimizerExtension` is registered with the schema. Without it, field-level `prefetch_related=` hints are silently ignored.

`Grep` for `DjangoOptimizerExtension` in `*.py` (commonly `*/schema.py`, `*/apps.py`, or wherever the schema is constructed). Three outcomes:

- **Found and registered as a schema extension** (e.g. `Schema(extensions=[DjangoOptimizerExtension])`) → Option A is available. Cite the `path:LINE` on the Recommendation.
- **Imported but not registered with the schema** → Option A is *not* in effect. Treat as "missing": lead with Option B, add a `Notes` line: "DjangoOptimizerExtension is imported but not registered with the schema; field-level hints will not apply until it's added to `Schema(extensions=[...])`."
- **Not found at all** → Option A requires enabling the extension first. Lead with Option B (upstream prefetch in the queryset builder). Mention enabling the extension as a follow-up improvement, not the primary fix.

Also locate the **queryset builder** that feeds the resolver — typically a `get_<entity>` query function, a manager method, or a ViewSet/router-style helper. This anchors the `Prefetch site` line and is where Option B's prefetch lives.

## Fix structure

For each finding, present both options and a project-aware recommendation.

### Option A — Framework-native (field-level hint)

Co-locates the optimization with the field. Triggered selection-aware via `DjangoOptimizerExtension`. Two sub-shapes:

**A1 — SQL-filter (callable `Prefetch` hint).** One filtered query, only matching rows in cache.

```python
@strawberry_django.field(
    prefetch_related=[
        lambda info: Prefetch(
            'line_items',
            queryset=LineItem.objects.select_related('product').filter(is_active=True),
            to_attr='active_line_items',
        )
    ],
)
def active_line_items(self) -> list[LineItemType]:
    return self.active_line_items
```

**A2 — Python-filter (string hint + comprehension).** Whole relation cached once, predicate applied in Python. Multiple subsets of the same relation share one prefetch.

```python
@strawberry_django.field(prefetch_related=['line_items__product'])
def active_line_items(self) -> list[LineItemType]:
    return [li for li in self.line_items.all() if li.is_active]
```

Sub-shape trade-off (use verbatim if both A1 and A2 apply):

> Pick A1 if the relation can be large or you only need one subset. Pick A2 if the relation is small and bounded or you need multiple subsets (partition once, one query total).

**When A2 is invalid:** if the comprehension predicate calls `.filter()`, `.exists()`, `.count()`, `Model.objects.*`, or any ORM method, do *not* propose A2 — that turns N+1 into N×M. Only A1 applies.

### Option B — Upstream ORM prefetch

Prefetch lives in the queryset builder identified during Prerequisites — outside the resolver, on the queryset that feeds it. Same SQL-filter / Python-filter sub-shapes as plain Django.

```python
# In the queryset builder (e.g. get_campaign_reviews):
return Review.objects.prefetch_related(
    Prefetch(
        'star_ratings',
        queryset=Rating.objects.select_related('question').filter(question__is_additional=False),
        to_attr='_active_star_ratings',
    )
)

# In the resolver:
@strawberry_django.field()
def star_ratings(self, parent: strawberry.Parent) -> list[RatingType]:
    return parent._active_star_ratings
```

### Recommendation rule

State the selected option in one sentence on the Fix block, citing project signals from Prerequisites:

- **DjangoOptimizerExtension is registered AND the queryset builder is shared by multiple views/callsites** → prefer **Option A**. Selection-aware (only prefetches when the field is queried), co-located with the field, impossible to forget.
- **DjangoOptimizerExtension is NOT registered** → only **Option B** is valid right now. Mention enabling the extension as an optional follow-up improvement.
- **Queryset builder is dedicated to this view AND the field is unconditional in the GraphQL response** → either works. Prefer **Option B** for explicitness — the cost of always-prefetching is irrelevant when the field is always selected.
- **Predicate or sub-relation is shared with non-GraphQL paths** (admin, exports, Celery, internal services) → prefer **Option B**, or move the predicate to a `@model_property(prefetch_related=...)` (see below) so the optimization applies in both GraphQL and Python contexts.

## `@model_property` / `@cached_model_property`

Same two sub-shapes at the model layer when the computed value is reused outside GraphQL:

```python
@model_property(prefetch_related=['line_items__product'])
def active_line_items(self) -> list:
    return [li for li in self.line_items.all() if li.is_active]
```

Treat as a third option when the field is consumed by both GraphQL and non-GraphQL callers — gets the optimizer hint *and* works in admin/exports.

## Doc grounding

When emitting a strawberry-django finding, `WebFetch` the optimizer guide and cite the URL plus the detected version on the `Reference` line:

- Optimizer: https://strawberry.rocks/docs/django/guide/optimizer
- Model properties: https://strawberry.rocks/docs/django/guide/model-properties

Format: `https://… (strawberry-graphql-django <version>)`.

## Version notes

| Detected version | Note |
|---|---|
| `< 0.10` | Selection-aware optimizer was added around 0.10. Earlier versions don't dedupe hints across siblings. Add `Notes: upgrade strongly recommended` and treat field-level hints as best-effort. |
| `0.10` – current | Both options apply. If a finding involves nested `Prefetch` queryset chaining and the `WebFetch` doc shows version-specific guidance, cite it. |
