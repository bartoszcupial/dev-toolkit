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
| feature-dev | Comprehensive feature development workflow with specialized agents (from Anthropic) | `/plugin install feature-dev@dev-toolkit` |

## Contributing

1. Create your plugin folder under `plugins/`
2. Follow the plugin structure (see `plugins/project-maintainer/` as example)
3. Add entry to `.claude-plugin/marketplace.json`
4. Submit PR

## Adding Plugins from Other Sources

You can also add plugins from external repos to this marketplace.

**Local plugin (in this repo):**
```json
{
  "name": "my-plugin",
  "description": "What it does",
  "source": "./plugins/my-plugin"
}
```

**GitHub repo:**
```json
{
  "name": "cool-plugin",
  "description": "A public plugin I like",
  "source": {
    "source": "github",
    "repo": "owner/repo-name"
  }
}
```

**Any git URL:**
```json
{
  "name": "team-plugin",
  "description": "Plugin from another team",
  "source": {
    "source": "url",
    "url": "https://github.com/org/plugin-repo.git"
  }
}
```

This lets you curate a mix of internal and external plugins in one marketplace.

## Plugin Requirements

- Must have `.claude-plugin/plugin.json`
- Must have `README.md` with usage instructions
- Should follow Claude Code plugin philosophy (minimal permissions, user consent)
