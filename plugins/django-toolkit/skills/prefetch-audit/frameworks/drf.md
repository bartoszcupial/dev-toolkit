# DRF overlay

Apply when `FRAMEWORKS_INSTALLED` lists `djangorestframework:<version>`. Linked from `SKILL.md`.

## Per-parent callsites in DRF

These methods are invoked once per object during list serialization. Treat them as per-parent.

- `get_<field>(self, obj)` — bound resolver for a `SerializerMethodField`.
- `to_representation(self, instance)` — runs once per item in a `ListSerializer`.
- `Serializer` field types that touch relations: `PrimaryKeyRelatedField(queryset=...)` (writable serializers), `SlugRelatedField`, nested writable `Serializer` / `ListSerializer`.
- Methods on a `ModelSerializer` referenced from `Meta.fields` that compute values from related managers.
- **Model `@property` / `@cached_property` referenced from `Meta.fields` or read inside `get_<field>` / `to_representation`.** A property that runs an ORM query (e.g. `Model.objects.annotate(...).get(id=self.id)` or `self.related.filter(...)`) executes per-row during list serialization. Open the property definition — if it touches the database, the entire field is per-parent regardless of the serializer code looking innocuous.

## Where the prefetch belongs

Upstream, on the queryset that feeds the list endpoint. Common placements:

- `ViewSet.get_queryset()` — most common. Returns `Model.objects.prefetch_related(...).select_related(...)`.
- `APIView.get_queryset()` for non-ViewSet endpoints.
- The `setup_eager_loading` idiom (manual classmethod on the serializer that takes a queryset and applies `select_related` / `prefetch_related` based on the serializer's declared fields). The view calls `Serializer.setup_eager_loading(queryset)` before passing to `Serializer(qs, many=True)`.
- A queryset helper or manager method called from `get_queryset`.

If the resolver / `get_<field>` chains an ORM verb on a related manager (`obj.children.filter(...)`, `obj.children.count()`), the upstream prefetch is bypassed regardless of where it lives. The fix is to either consume the cache (`obj.children.all()` plus Python-side filtering, or a `Prefetch(..., to_attr=)` with `obj.<to_attr>`) or push the filter into the upstream `Prefetch`.

## Common DRF-specific traps

- **`source='related__field'` dotted paths.** A read-only field with `source='customer__company__name'` triggers FK traversal per row unless every step is `select_related`. Flag if the upstream queryset doesn't have `select_related` matching the dotted path.
- **`PrimaryKeyRelatedField(queryset=Model.objects.all())` on a writable serializer.** The validation queryset evaluates per-instance during write. Not an N+1 in the serialization path, but worth flagging if the queryset is itself expensive.
- **Nested writable serializers.** `OrderSerializer` with a nested `LineItemSerializer(many=True)` where the parent's `create`/`update` iterates children — each child save can trigger queries; check if the parent prefetched.
- **Pagination interaction.** `PageNumberPagination` over an unprefetched queryset N+1's once per page item. Verify the paginated viewset's `get_queryset` includes the prefetch.

## Fix patterns (apply the cross-framework patterns from SKILL.md)

The two fix shapes that apply: upstream `Prefetch(..., to_attr=)` with SQL-side filtering (Pattern A), or upstream string-form `prefetch_related` plus Python-side comprehension (Pattern B). Same Pattern B validity rule: ORM calls in the comprehension are forbidden.

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
