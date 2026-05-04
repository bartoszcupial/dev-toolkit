# Django Ninja overlay

Apply when `FRAMEWORKS_INSTALLED` lists `django-ninja:<version>`. Linked from `SKILL.md`.

## Per-parent callsites in Ninja

- `Schema.resolve_<field>(obj)` — staticmethod / classmethod resolver, called once per object when the schema serializes a list response.
- `@api.get` / `@router.get` handlers iterating a queryset and constructing schemas in the loop.
- `Schema.from_orm(model_instance)` calls inside a list response — each call evaluates resolvers per instance.
- Property-style schema fields that touch relations.

## Where the prefetch belongs

Upstream, on the queryset *before* it's converted to schemas. Common placements:

- The route handler itself — `Order.objects.prefetch_related(...).all()` returned to a `list[OrderSchema]` response.
- A queryset helper (manager method, view-level helper) called from the route handler.
- A custom `Schema.Config.from_orm` override — but uncommon; usually the route handler does the work.

`Schema.from_orm` doesn't trigger prefetch on its own; it just reads attributes. If the queryset wasn't prefetched upstream, every `resolve_<field>` that touches a relation N+1's silently.

## Ninja-specific traps

- **Serialization timing.** Ninja serializes the response *after* the route handler returns. If the handler returns a `QuerySet`, evaluation happens during serialization and any deferred work (annotations, prefetches) runs then. If the handler `list()`s the queryset early, prefetches still apply but you've lost laziness for further chaining. Either is fine — just make sure the prefetch was applied before the queryset is consumed.
- **`Schema.resolve_<field>` chaining ORM verbs.** The trap mirrors strawberry's: a resolver doing `obj.children.filter(...)` bypasses any upstream prefetch. Fix: consume the cache or push the filter upstream.
- **Async handlers (`async def`) and `sync_to_async` wrappers.** When the route is async, you may see `sync_to_async(list)(queryset)` patterns. The prefetch still works, but verify the queryset was prefetched before the wrapper, not after.
- **Nested schemas.** `OrderSchema` containing `line_items: list[LineItemSchema]` — each `LineItemSchema` instantiation per row N+1's if `line_items` wasn't prefetched on the parent queryset.

## Fix pattern

Pattern A or B from SKILL.md — same as DRF, applied at the route-handler layer.

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
