# Command Output Parsing Reference

This reference covers parsing output from native package manager tools.

## JSON Output Formats

### npm outdated --json

```json
{
  "package-name": {
    "current": "1.0.0",
    "wanted": "1.0.5",
    "latest": "2.0.0",
    "dependent": "project-name"
  }
}
```

Key fields:
- `current`: Currently installed version
- `wanted`: Latest version that satisfies version constraints (safe update)
- `latest`: Absolute latest version (may be major/breaking)

### pip list --outdated --format json

```json
[
  {
    "name": "package-name",
    "version": "1.0.0",
    "latest_version": "1.2.0",
    "latest_filetype": "wheel"
  }
]
```

## Table Output Notes

Some commands output tables instead of JSON:

- `yarn outdated`: Outputs a table with columns: Package, Current, Wanted, Latest, Package Type, URL
- `pipenv update --outdated`: Outputs text lines like "Package 'foo' out of date: X installed, Y available"
- `poetry show --outdated`: Outputs a table with columns: name, version, latest

Parse these by splitting on whitespace and identifying columns by position.
