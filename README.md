# Dev Toolkit

Custom Claude Code plugins for development workflows.

## Setup (One-time)

Add this marketplace in Claude Code:

```
/plugin marketplace add bartoszcupial/dev-toolkit
```

## Updating

To get the latest plugins, manually update the marketplace:

```
/plugin marketplace update dev-toolkit
```

You can also enable auto-updates via `/plugin` → **Marketplaces** → select `dev-toolkit` → **Enable auto-update**. See [Configure auto-updates](https://code.claude.com/docs/en/discover-plugins#configure-auto-updates) for details.

## Available Plugins

| Plugin | Description | Install |
|--------|-------------|---------|
| project-maintainer | Dependency updates with changelog analysis | `/plugin install project-maintainer@dev-toolkit` |
| django-toolkit | Django ORM audits and base setup. Strawberry-django, DRF, and Django Ninja aware. | `/plugin install django-toolkit@dev-toolkit` |

## Contributing

1. Create your plugin folder under `plugins/`
2. Follow the plugin structure (see `plugins/project-maintainer/` as example)
3. Add entry to `.claude-plugin/marketplace.json`
4. Submit PR

## Plugin Requirements

- Must have `.claude-plugin/plugin.json`
- Must have `README.md` with usage instructions
- Should follow Claude Code plugin philosophy (minimal permissions, user consent)
