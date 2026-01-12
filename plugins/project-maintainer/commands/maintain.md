---
description: "Analyze outdated packages, fetch changelogs, and identify code impact"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "WebFetch"]
disable-model-invocation: true
---

# Project Maintenance Command

Analyze project dependencies for updates, with focus on understanding breaking changes and their impact on the codebase.

Respect any scope limitations the user mentions (e.g., "backend only", "just frontend", "skip python").

## Scope

This command provides **intelligent update analysis**:
- Identify outdated packages
- For major updates: fetch and analyze changelogs
- Search codebase for impacted code
- Provide migration guidance

For security vulnerability scanning, check your CI pipeline.

## Workflow

### 1. Confirm Directory

Before scanning, confirm the working directory with the user.

### 2. Check Local Settings

Check if `.claude/project-maintainer.local.md` exists in the project:
- If present, read YAML frontmatter for settings:
  - `skip_packages`: List of packages to exclude from analysis
  - `custom_changelogs`: Package-to-URL mappings for changelog overrides
- If missing, proceed with defaults silently (do not prompt to create)

### 3. Identify Outdated Packages

Use the appropriate package manager tool to list outdated packages. See the maintenance-patterns skill for commands.

If local settings include `skip_packages`, exclude those from the results.

Categorize by update type:
- **Patch/minor**: Note for potential batch update
- **Major**: Flag for detailed changelog analysis

### 4. Analyze Major Updates

For each package with a major version update:

1. **Check for changelog overrides**
   - First check local settings `custom_changelogs` for project-specific URLs
   - Then check `references/changelog-exceptions.md` for known changelog locations

2. **Find the changelog** (if not in exceptions)
   - Get package metadata (repository URL)
   - Fetch the repository landing page
   - Extract links to releases/changelog
   - Follow the links to get changelog content

3. **Identify breaking changes**
   - Look for "Breaking Changes", "Migration", "Upgrading" sections
   - Note removed/renamed APIs, changed behaviors, new requirements

4. **Search codebase for impact**
   - For each breaking change, search for affected code
   - Use Grep to find usages of deprecated/removed APIs
   - Report file paths and line numbers

5. **Suggest migrations**
   - Based on changelog guidance, suggest code changes
   - Provide specific replacements where possible

### 5. Summarize Findings

Present findings to the user:

**Safe updates (patch/minor):**
- List packages that can be batch updated

**Breaking changes (major):**
For each:
- What changed (from changelog)
- Where it affects your code (file:line)
- How to fix it (migration suggestion)

### 6. Ask User Before Any Changes

Always ask user before:
- Applying batch updates
- Making any code changes

Request Edit/Write permissions only when user explicitly approves.

### 7. Verification Reminder

After any updates are applied, remind users to verify:
- Run the project's test suite
- Check for deprecation warnings in test output
- Verify the application starts correctly
- Test critical user flows manually

## Key Behaviors

- Focus analysis effort on **major version updates**
- Always fetch changelogs before declaring something "breaking"
- Search the actual codebase - don't assume impact
- Provide actionable migration guidance, not just warnings
- **Ask user before any updates** - present findings, get explicit approval
- Use shell commands only for fact-gathering (outdated list, grep hits, metadata)
