# Strawberry-django overlay

Apply when `FRAMEWORKS_INSTALLED` lists `strawberry-graphql-django:<version>`. Linked from `SKILL.md`.

## What's unique here

Strawberry-django's `DjangoOptimizerExtension` reads field-level `prefetch_related=` / `select_related=` hints and applies them **selection-aware**: it prefetches only what the GraphQL query asks for, and dedupes identical hints across sibling resolvers.

**The trap:** the optimizer applies the hint only when the resolver **consumes the cache** via `.all()` or accesses a `to_attr`. If the resolver chains `.filter()` / `.exclude()` / `.order_by()` etc. on the related manager, the hint silently no-ops. The prefetch query still runs (wasted), and the resolver fires its own per-parent query on top.

```python
@strawberry_django.field(prefetch_related=['line_items'])
def active_line_items(self) -> list[LineItemType]:
    return self.line_items.filter(is_active=True)   # ← bypasses the hint, N+1
```

On a `@strawberry_django.type` the resolver receives `self` as the model instance; there is no second `parent` argument.

## Two idiomatic fix shapes

Both are documented as valid. Show both unless the predicate disqualifies the second.

**Shape 1 — SQL-filter (callable `Prefetch` hint).** One filtered query, only matching rows in cache.

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

**Shape 2 — Python-filter (string hint + comprehension).** Whole relation cached once, predicate applied in Python. Multiple subsets of the same relation share one prefetch.

```python
@strawberry_django.field(prefetch_related=['line_items__product'])
def active_line_items(self) -> list[LineItemType]:
    return [li for li in self.line_items.all() if li.is_active]
```

Trade-off line for the `Fix` section (use verbatim):

> Pick the SQL-filter shape if the relation can be large or you only need one subset. Pick the Python-filter shape if the relation is small and bounded or you need multiple subsets (partition once, one query total).

**When Shape 2 is invalid:** if the comprehension predicate calls `.filter()`, `.exists()`, `.count()`, `Model.objects.*`, or any ORM method, do *not* propose Shape 2 — that turns N+1 into N×M. Only Shape 1 applies. Plain attribute reads (`if c.is_active`, `if c.category.is_visible` when category was prefetched) are fine.

## `@model_property` / `@cached_model_property`

Same two shapes at the model layer when the computed value is reused outside GraphQL (admin, exports, tasks):

```python
@model_property(prefetch_related=['line_items__product'])
def active_line_items(self) -> list:
    return [li for li in self.line_items.all() if li.is_active]
```

## Doc grounding

When emitting a strawberry-django finding, `WebFetch` the optimizer guide and cite the URL plus the detected version on the `Reference` line:

- Optimizer: https://strawberry.rocks/docs/django/guide/optimizer
- Model properties: https://strawberry.rocks/docs/django/guide/model-properties

Format: `https://… (strawberry-graphql-django <version>)`.

## Version notes

| Detected version | Note |
|---|---|
| `< 0.10` | Selection-aware optimizer was added around 0.10. Earlier versions don't dedupe hints across siblings. Add `Notes: upgrade strongly recommended` and treat field-level hints as best-effort. |
| `0.10` – current | Both fix shapes apply. If a finding involves nested `Prefetch` queryset chaining and the WebFetch doc shows version-specific guidance, cite it. |
