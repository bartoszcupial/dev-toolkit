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
# In the queryset builder (e.g. get_orders_for_user):
return Order.objects.prefetch_related(
    Prefetch(
        'line_items',
        queryset=LineItem.objects.select_related('product').filter(is_active=True),
        to_attr='_active_line_items',
    )
)

# In the resolver:
@strawberry_django.field()
def active_line_items(self, parent: strawberry.Parent) -> list[LineItemType]:
    return parent._active_line_items
```

### Evaluation rule (bidirectional)

Apply both directions — Option A is **not** the default winner just because the framework is wired up. Use the Pre-flight signals (which exist in the audit output) to decide. The verdict on each option must cite one or more of: `DjangoOptimizerExtension`, `Queryset builder for target`, `Other consumers of that queryset builder`, plus this finding's `Why it breaks`.

**Pick Option A (framework-native) when:**

- DjangoOptimizerExtension is registered, AND
- the field is *conditionally* selected by clients (some queries skip it) — selection-awareness saves the prefetch query when the field is absent, OR
- the same predicate appears on resolvers in multiple types and there is no centralizing queryset builder — field-level hint prevents drift, OR
- the resolver is genuinely GraphQL-only with no non-GraphQL consumers.

**Pick Option B (upstream ORM) — even when DjangoOptimizerExtension is registered — when:**

- the queryset builder is shared with non-GraphQL paths (admin, exports, Celery, internal services) — single prefetch site beats fragmented hints, OR
- the field is unconditionally selected in every GraphQL query — selection-awareness offers no benefit, upstream is simpler and more debuggable, OR
- multiple subsets of the same relation are needed — one upstream `prefetch_related` with Python-filter is cleaner than two field-level hints, OR
- the relation is the model's central relation and is always touched anyway — push it to the queryset builder or a manager method.

**Pick Option B by force when:**

- DjangoOptimizerExtension is **not** registered — Option A's verdict line states "No — DjangoOptimizerExtension not found; field-level hints will not apply." Optionally mention "enabling the extension is a follow-up improvement," but do not present Option A as the recommendation.

When Pre-flight signals are insufficient to pick a winner (e.g. you couldn't determine whether the queryset builder has other consumers), state that on both verdict lines and pick the safer choice — usually Option B — and label the residual ambiguity in `Notes`.

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
