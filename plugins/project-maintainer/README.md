# Project Maintainer

Intelligent dependency management with changelog analysis and code impact detection.

## Features

- **Outdated package detection** - Identifies packages that can be updated
- **Changelog analysis** - Fetches and summarizes breaking changes from release notes
- **Code impact search** - Finds where your code uses deprecated/removed APIs
- **Migration guidance** - Suggests specific code changes based on changelogs

For security vulnerability scanning (CVEs, secrets, misconfigurations), check your CI pipeline.

## Usage

```
/project-maintainer:maintain
```

Natural language scoping:
```
/project-maintainer:maintain backend only
/project-maintainer:maintain just frontend
```

## Workflow

1. **Confirm directory** - Verify which directory will be scanned
2. **Check local settings** - Apply project-specific configuration if present
3. **Identify outdated packages** - Using native package manager tools
4. **Analyze major updates** - Fetch changelogs, identify breaking changes
5. **Search codebase for impact** - Find where deprecated APIs are used
6. **Summarize findings** - Safe updates vs breaking changes with migration guidance
7. **Ask before any changes** - User approves updates explicitly
8. **Verification reminder** - Prompt to run tests after updates

## Configuration (Optional)

The plugin works out of the box with no configuration required. For project-specific settings, create `.claude/project-maintainer.local.md`:

```yaml
---
skip_packages:
  - internal-company-lib
  - legacy-wrapper
custom_changelogs:
  our-design-system: https://internal-docs.company.com/design-system/changelog
---

## Project Notes

Any notes about dependency management for this project...
```

### Available Settings

| Setting | Description |
|---------|-------------|
| `skip_packages` | Packages to exclude from analysis (e.g., internal packages) |
| `custom_changelogs` | Override changelog URLs for specific packages |

To create this file, ask Claude: "Create a project-maintainer config file for this project"

## Supported Package Managers

| Language | Package Managers |
|----------|------------------|
| Python | uv, pipenv, poetry, pdm, pip |
| JavaScript/TypeScript | yarn, npm, pnpm, bun |

Detection is automatic based on lock files (`uv.lock`, `Pipfile.lock`, `poetry.lock`, `yarn.lock`, `package-lock.json`, etc.)

## Example Output

```
Project Maintenance Analysis

Directory: /Users/you/projects/my-app
Package Manager: pipenv (Pipfile.lock)

Safe Updates (patch/minor):
• requests 2.31.0 → 2.32.0 (minor)
• django 4.2.10 → 4.2.11 (patch)

Breaking Changes (major):

celery 5.3.6 → 6.0.0
├─ Breaking: Removed `task_always_eager` setting
│  Found in: backend/settings.py:45
│  Migration: Use `task_always_eager` in task decorator instead
├─ Breaking: Changed `apply_async` signature
│  Found in: backend/tasks/email.py:23, backend/tasks/reports.py:67
│  Migration: Update to use keyword arguments

Apply safe updates? [Y/n]
```
