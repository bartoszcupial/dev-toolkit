# Django Ninja overlay

Apply when `django-ninja` is confirmed in the environment-detection summary. Linked from `SKILL.md`.

Like DRF, Ninja has **no selection-aware optimizer** — `Schema.from_orm` just reads attributes. The framework-native answer for prefetching *is* upstream `prefetch_related` on the queryset returned by the route handler. So this overlay presents a single canonical fix shape; the work the `Prerequisites` rule does for Ninja is locating *where* upstream lives.

## Per-parent callsites in Ninja

- `Schema.resolve_<field>(obj)` — staticmethod / classmethod resolver, called once per object when the schema serializes a list response.
- `@api.get` / `@router.get` handlers iterating a queryset and constructing schemas in the loop.
- `Schema.from_orm(model_instance)` calls inside a list response — each call evaluates resolvers per instance.
- Property-style schema fields that touch relations.

## Prerequisites

Before writing the Fix, locate the **prefetch site** — i.e. where the queryset returned by the route handler originates. This anchors the fix at the right `path:LINE` and reveals scope.

`Grep` and read in this order:

1. **The route handler** for this schema (`Grep` the schema class name across `api.py` / `routers/*.py`). Determine the queryset source:
   - Inline `Model.objects.…` in the handler body → the handler is the prefetch site.
   - Returns a queryset from a helper (`get_orders(...)`) or manager method (`Order.objects.for_user(user)`) → the helper is the prefetch site.
   - `Schema.from_orm(...)` called inside a loop → flag the loop body itself; the queryset feeding the loop is the prefetch site.
2. **`django-ninja-extra` controllers** — if installed, controllers may centralize queryset construction. `Grep` for `ControllerBase` or `@api_controller`. Different placement convention; treat the controller method as the prefetch site.
3. **Async handlers (`async def`) and `sync_to_async` wrappers** — confirm the prefetch is applied *before* the wrapper, not after. `sync_to_async(list)(qs)` evaluates the queryset; any `prefetch_related` chained after that point is a no-op.

Record the result on the finding's `Prefetch site:` line. If a `resolve_<field>` chains an ORM verb on a related manager (`obj.children.filter(...)`), the upstream prefetch is bypassed regardless of placement — the fix must either consume the cache or push the filter into the upstream `Prefetch`.

## Ninja-specific traps

- **Serialization timing.** Ninja serializes the response *after* the route handler returns. If the handler returns a `QuerySet`, evaluation happens during serialization and any deferred work (annotations, prefetches) runs then. If the handler `list()`s the queryset early, prefetches still apply but you've lost laziness for further chaining. Either is fine — just make sure the prefetch was applied before the queryset is consumed.
- **`Schema.resolve_<field>` chaining ORM verbs.** The trap mirrors strawberry's: a resolver doing `obj.children.filter(...)` bypasses any upstream prefetch. Fix: consume the cache or push the filter upstream.
- **Async handlers (`async def`) and `sync_to_async` wrappers.** When the route is async, you may see `sync_to_async(list)(queryset)` patterns. The prefetch still works, but verify the queryset was prefetched before the wrapper, not after.
- **Nested schemas.** `OrderSchema` containing `line_items: list[LineItemSchema]` — each `LineItemSchema` instantiation per row N+1's if `line_items` wasn't prefetched on the parent queryset.

## Fix structure (single canonical option)

Ninja doesn't expose a framework-native shortcut distinct from upstream prefetch — the canonical fix is upstream `prefetch_related` at the prefetch site identified in Prerequisites (route handler, queryset helper, or controller method). The two ORM sub-shapes from `SKILL.md` apply: SQL-filter (`Prefetch(..., to_attr=)` with filtered inner queryset) or Python-filter (string-form `prefetch_related` + comprehension). Same Pattern B validity rule: ORM calls in the comprehension are forbidden.

When both sub-shapes are valid, present both with the trade-off line from `SKILL.md`. The placement is determined by Prerequisites, not by sub-shape choice.

```python
# Route handler:
@router.get("/orders", response=list[OrderSchema])
def list_orders(request):
    return Order.objects.prefetch_related(
        Prefetch(
            'line_items',
            queryset=LineItem.objects.select_related('product').filter(is_active=True),
            to_attr='active_line_items',
        )
    )

# Schema:
class OrderSchema(Schema):
    id: int
    active_line_items: list[LineItemSchema]

    @staticmethod
    def resolve_active_line_items(obj):
        return obj.active_line_items   # consumes the to_attr
```

## Doc grounding

When emitting a Ninja finding, `WebFetch` the relevant section and cite the URL on the `Reference` line:

- Ninja Schemas: https://django-ninja.dev/guides/response/django-pydantic/
- Ninja queryset/response handling: https://django-ninja.dev/guides/response/

Format: `https://… (django-ninja <version>)`.

## Version notes

| Detected version | Note |
|---|---|
| `0.x` | Older API; `Schema.from_orm` was the only path. Apply the audit, but verify resolver signatures match `(obj)` not `(self, obj)`. |
| `1.x` | Current. `resolve_<field>` is the standard resolver; both staticmethod and classmethod forms work. Apply the audit as-is. |
