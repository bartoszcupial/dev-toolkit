# DRF overlay

Apply when `djangorestframework` is confirmed in the environment-detection summary. Linked from `SKILL.md`.

DRF has **no selection-aware optimizer extension** distinct from upstream prefetch. The framework-native answer for prefetching *is* upstream `prefetch_related` on the queryset that feeds the view. So this overlay presents a single canonical fix shape; the work the `Prerequisites` rule does for DRF is locating *where* upstream lives.

## Per-parent callsites in DRF

These methods are invoked once per object during list serialization. Treat them as per-parent.

- `get_<field>(self, obj)` — bound resolver for a `SerializerMethodField`.
- `to_representation(self, instance)` — runs once per item in a `ListSerializer`.
- `Serializer` field types that touch relations: `PrimaryKeyRelatedField(queryset=...)` (writable serializers), `SlugRelatedField`, nested writable `Serializer` / `ListSerializer`.
- Methods on a `ModelSerializer` referenced from `Meta.fields` that compute values from related managers.
- **Model `@property` / `@cached_property` referenced from `Meta.fields` or read inside `get_<field>` / `to_representation`.** A property that runs an ORM query (e.g. `Model.objects.annotate(...).get(id=self.id)` or `self.related.filter(...)`) executes per-row during list serialization. Open the property definition — if it touches the database, the entire field is per-parent regardless of the serializer code looking innocuous.

## Prerequisites

Before writing the Fix, locate the **prefetch site** — i.e. where the queryset feeding this serializer originates. This anchors the fix at the right `path:LINE` and reveals scope (one view vs many).

`Grep` and read in this order:

1. **The view class** that uses this serializer (`Grep` the serializer's class name across `views.py` / `viewsets.py`). Determine the queryset source:
   - `get_queryset(self)` override → that's the prefetch site.
   - `queryset = Model.objects.…` class attribute → convert to `get_queryset()` to add the prefetch (or extend the class attribute), and note this in the fix.
   - Inherits a base ViewSet / mixin → check the base for an existing `get_queryset`; the prefetch may belong there if multiple views share it.
2. **The `setup_eager_loading` idiom** — `Grep` for `setup_eager_loading` in the serializer class. If present, the prefetch belongs there (declared per-field, applied by the view before `many=True`). If absent and many serializers in the project share fields, mention it as a structural improvement, not a per-finding fix.
3. **Pagination wrappers** — confirm the paginated viewset's `get_queryset` is what's actually iterated. `PageNumberPagination` over an unprefetched queryset N+1's per page item.

Record the result on the finding's `Prefetch site:` line. If the resolver / `get_<field>` chains an ORM verb on a related manager (`obj.children.filter(...)`, `obj.children.count()`), the upstream prefetch is bypassed regardless of where it lives — the fix must either consume the cache or push the filter into the upstream `Prefetch`.

## Common DRF-specific traps

- **`source='related__field'` dotted paths.** A read-only field with `source='customer__company__name'` triggers FK traversal per row unless every step is `select_related`. Flag if the upstream queryset doesn't have `select_related` matching the dotted path.
- **`PrimaryKeyRelatedField(queryset=Model.objects.all())` on a writable serializer.** The validation queryset evaluates per-instance during write. Not an N+1 in the serialization path, but worth flagging if the queryset is itself expensive.
- **Nested writable serializers.** `OrderSerializer` with a nested `LineItemSerializer(many=True)` where the parent's `create`/`update` iterates children — each child save can trigger queries; check if the parent prefetched.
- **Pagination interaction.** `PageNumberPagination` over an unprefetched queryset N+1's once per page item. Verify the paginated viewset's `get_queryset` includes the prefetch.

## Fix structure (single canonical option)

DRF doesn't expose a framework-native shortcut distinct from upstream prefetch — the canonical fix is upstream `prefetch_related` at the prefetch site identified in Prerequisites. The two ORM sub-shapes from `SKILL.md` apply: SQL-filter (`Prefetch(..., to_attr=)` with filtered inner queryset) or Python-filter (string-form `prefetch_related` + comprehension). Same Pattern B validity rule: ORM calls in the comprehension are forbidden.

When both sub-shapes are valid, present both with the trade-off line from `SKILL.md`. The placement (`get_queryset` / `setup_eager_loading` / shared mixin) is determined by Prerequisites, not by sub-shape choice.

```python
# ViewSet upstream:
class OrderViewSet(viewsets.ModelViewSet):
    def get_queryset(self):
        return Order.objects.prefetch_related(
            Prefetch(
                'line_items',
                queryset=LineItem.objects.select_related('product').filter(is_active=True),
                to_attr='active_line_items',
            )
        )

# Serializer:
class OrderSerializer(serializers.ModelSerializer):
    active_line_items = serializers.SerializerMethodField()

    def get_active_line_items(self, obj):
        return LineItemSerializer(obj.active_line_items, many=True).data
```

## Doc grounding

When emitting a DRF finding, `WebFetch` the relevant section and cite the URL on the `Reference` line:

- DRF serializers: https://www.django-rest-framework.org/api-guide/serializers/
- DRF generic views: https://www.django-rest-framework.org/api-guide/generic-views/

Format: `https://… (djangorestframework <version>)`.

## Version notes

DRF's resolver and serialization mechanics have been stable since 3.x. No version-gated behavior changes relevant to this audit. If a finding involves a recently-added serializer feature, verify against the changelog.
