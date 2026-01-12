# Changelog Exceptions

Overrides for packages with non-standard changelog locations. Use these when the discovery algorithm doesn't find the changelog automatically.

This is a small curated list, not a directory. Add your frequently used packages as you discover their locations.

## Frameworks with Doc-Based Release Notes

These frameworks publish release notes on their documentation sites rather than GitHub releases:

| Package | Release Notes Location |
|---------|----------------------|
| Django | `https://docs.djangoproject.com/en/<version>/releases/` |
| Flask | `https://flask.palletsprojects.com/en/latest/changes/` |
| Celery | `https://docs.celeryq.dev/en/stable/history/` |
| SQLAlchemy | `https://docs.sqlalchemy.org/en/latest/changelog/` |

## Your Frequently Used Packages

Add your top 10-20 packages here as you discover their changelog locations.

| Package | Changelog Location | Notes |
|---------|-------------------|-------|
| | | |

## How to Add Entries

When the discovery algorithm fails for a package you use often:

1. Find the changelog manually
2. Add it to the table above
3. The plugin will check this file before using the discovery algorithm

Keep this list small - only add packages where:
- The discovery algorithm consistently fails
- You update the package frequently
- The changelog location is stable
