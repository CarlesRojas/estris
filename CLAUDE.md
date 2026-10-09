# Notes for Claude

- Project context (features, settings, behavior, project structure) lives in `PROJECT.md`. Read it for context, and keep it up to date whenever a feature or the structure changes.
- `README.md` only covers how to develop: the commands and a short line for each. Keep it short.
- Localization: every user-facing string must be localized in the same change that adds or edits it, in every supported language, with no exceptions and no follow-up PRs. A string is user-facing if it can appear on screen (labels, buttons, menus, alerts, help tooltips, placeholders, Event Viewer text). Log messages and identifiers are not localized.
  - How: add the English text as a line in every `Resources/Localization/<language>.lproj/Localizable.strings` (the key is the English text, with `%@` for interpolated strings and `%lld` for integers), translated. Literal text in SwiftUI (`Text("…")`, `Button("…")`, `.help("…")`) is translated on its own; text built in code uses `String(localized: "…")`; a key known only at run time uses `localized(_:)`. Text that must never be translated uses `Text(verbatim:)`.
  - Then run `python3 scripts/check-localization.py`; it must report 0 problems before committing.
