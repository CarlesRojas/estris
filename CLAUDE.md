# Notes for Claude

- Project context (features, settings, behavior, project structure) lives in `PROJECT.md`. Read it for context, and keep it up to date whenever a feature or the structure changes.
- `README.md` only covers how to develop: the commands and a short line for each. Keep it short.
- Localization: every user-facing string must be localized in the same change that adds or edits it, in every supported language, with no exceptions and no follow-up PRs. A string is user-facing if it can appear on screen (labels, buttons, menus, alerts, help tooltips, placeholders, Event Viewer text). Log messages and identifiers are not localized.
