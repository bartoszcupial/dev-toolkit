---
name: maintenance-patterns
description: "Provides knowledge about dependency management, changelog discovery, and code impact analysis. Use when the user asks to maintain, update, or analyze breaking changes in project dependencies."
---

# Project Maintenance Patterns

Knowledge for intelligently managing software project dependencies.

## Package Manager Reference

### Python

| Lock File | Manager | Outdated Check | Update Command |
|-----------|---------|----------------|----------------|
| `uv.lock` | uv | `uv pip list --outdated` | `uv pip install --upgrade <pkg>` |
| `Pipfile.lock` | pipenv | `pipenv update --outdated` | `pipenv update <pkg>` |
| `poetry.lock` | poetry | `poetry show --outdated` | `poetry update <pkg>` |
| `pdm.lock` | pdm | `pdm outdated` | `pdm update <pkg>` |
| `requirements.txt` | pip | `pip list --outdated` | `pip install --upgrade <pkg>` |

### JavaScript/TypeScript

| Lock File | Manager | Outdated Check | Update Command |
|-----------|---------|----------------|----------------|
| `yarn.lock` | yarn | `yarn outdated` | `yarn upgrade <pkg>` |
| `package-lock.json` | npm | `npm outdated` | `npm update <pkg>` |
| `pnpm-lock.yaml` | pnpm | `pnpm outdated` | `pnpm update <pkg>` |
| `bun.lockb` | bun | `bun outdated` | `bun update <pkg>` |

### Multiple Lock Files

If a project has multiple lock files, the more specific format typically indicates the primary package manager. When ambiguous, ask the user.

### Unknown Package Managers

If you encounter a package manager not listed, check its documentation for equivalent commands.

---

## Changelog Discovery Algorithm

For major version updates, fetch and analyze changelogs to understand breaking changes.

### Step 1: Get Package Metadata

**Python (any manager):**
```bash
# pip/pipenv
pip show <package> | grep -E "Home-page|Project-URL"

# poetry
poetry show <package> | grep -i "home"

# uv
uv pip show <package> | grep -E "Home-page|Project-URL"

# pdm
pdm show <package>
```

Or fetch from PyPI API: `https://pypi.org/pypi/<package>/json`

**JavaScript (any manager):**
```bash
# npm
npm view <package> repository.url homepage

# yarn
yarn info <package> repository homepage

# pnpm
pnpm info <package> repository homepage

# bun
bun pm info <package>
```

Or fetch from npm registry: `https://registry.npmjs.org/<package>`

### Step 2: Fetch Landing Page & Extract Links

Use WebFetch on the repository or docs URL. From the page content, look for links to:
- `/releases` or `/tags` (release notes)
- `CHANGELOG`, `HISTORY`, `CHANGES` (changelog files)
- "Upgrading", "Migration", "What's New" (upgrade guides)

### Step 3: Follow Extracted Links

Fetch the changelog/release page. Look for the target major version.

### Step 4: Identify Breaking Changes

In the changelog content, search for:
- Sections: "Breaking Changes", "Breaking", "Incompatible", "Removed"
- Keywords: "removed", "deleted", "no longer", "renamed to", "now requires"
- Migration instructions

### Domain Allowlist

Restrict WebFetch to trusted sources:
- `github.com`, `gitlab.com`
- `pypi.org`, `npmjs.com`
- `docs.djangoproject.com`, `reactjs.org`, etc.

### Fallback: WebSearch

If metadata doesn't yield a repo URL, use WebSearch:
`"<package> <version> changelog breaking changes"`

But prefer the metadata → landing page → follow links approach.

---

## Code Impact Analysis

When a breaking change is identified from the changelog:

### Search Patterns

| Change Type | What to Search For |
|-------------|-------------------|
| Removed function | `from package import removed_func` or `package.removed_func` |
| Renamed function | Same search, suggest new name from changelog |
| Changed signature | Function calls with old argument names |
| Removed module | `import package.removed_module` |
| Changed default | Config or settings using old default behavior |

### Example Searches

Python:
```bash
# Django 4.0 removed force_text
grep -r "from django.utils.encoding import force_text"

# Django 5.0 removed USE_L10N setting
grep -r "USE_L10N"
```

JavaScript:
```bash
# React 18 removed componentWillMount
grep -r "componentWillMount"

# Next.js 13 changed pages to app directory
grep -r "getServerSideProps"
```

### Reporting Impact

For each breaking change found in codebase:
1. Report file path and line number
2. Show the affected code snippet
3. Suggest replacement based on changelog migration guide

---

## Update Classification

### Safe Updates (can batch apply)

- **Patch versions**: `1.2.3 → 1.2.4` (bug fixes)
- **Minor versions**: `1.2.3 → 1.3.0` (new features, backward compatible)

### Breaking Updates (analyze individually)

- **Major versions**: `1.x.x → 2.0.0` (breaking changes expected)
- Requires changelog analysis and code impact search

---

## Version Constraint Patterns

### Python

| Pattern | Meaning | Risk Level |
|---------|---------|------------|
| `*` | Any version | High - can get breaking changes |
| `~=1.2.3` | `>=1.2.3, <2.0.0` | Low - compatible releases |
| `>=1.2.3` | Any version above | Medium - no upper bound |
| `==1.2.3` | Exact version | Low - but may miss patches |

### JavaScript

| Pattern | Meaning | Risk Level |
|---------|---------|------------|
| `*` | Any version | High - can get breaking changes |
| `^1.2.3` | `>=1.2.3, <2.0.0` | Low - minor/patch only |
| `~1.2.3` | `>=1.2.3, <1.3.0` | Very low - patch only |
| `1.2.3` | Exact version | Low - but may miss patches |

---

## Local Settings

Projects can optionally have a `.claude/project-maintainer.local.md` file with YAML frontmatter:

```yaml
---
skip_packages:
  - internal-company-lib
  - legacy-wrapper
custom_changelogs:
  our-design-system: https://internal-docs.company.com/design-system/changelog
---
```

### Settings Reference

| Setting | Type | Description |
|---------|------|-------------|
| `skip_packages` | list | Packages to exclude from analysis |
| `custom_changelogs` | map | Package name → changelog URL overrides |

### Behavior

- Check for this file at the start of analysis
- If present, parse YAML frontmatter and apply settings
- If missing, proceed with defaults (do not prompt to create)
- `custom_changelogs` takes precedence over `references/changelog-exceptions.md`

---

## Reference Files

- `references/changelog-exceptions.md` - Overrides for packages with non-standard changelog locations
- `references/output-parsing.md` - Package manager output parsing details
