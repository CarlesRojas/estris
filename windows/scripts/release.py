#!/usr/bin/env python3
"""Prepares a Windows release: bumps the version in Estris.csproj and turns the changelog's
Unreleased section into the new version's. Used by the Release Windows workflow.

    python scripts/release.py patch|minor|major NOTES_FILE

Writes the release notes (the Unreleased entries, then a line every release has) to NOTES_FILE
and prints `version=X.Y.Z` for the workflow. Unreleased may be empty.
"""
import datetime
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "src/Estris/Estris.csproj"
CHANGELOG = ROOT / "CHANGELOG.md"
# Last in every release's notes, even when nothing else is.
ALWAYS = "- Performance improvements and bug fixes."


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("patch", "minor", "major"):
        sys.exit(__doc__)
    bump, notes_file = sys.argv[1], Path(sys.argv[2])

    changelog = CHANGELOG.read_text(encoding="utf-8")
    section = re.search(r"^## Unreleased\n(.*?)(?=^## |\Z)", changelog, re.S | re.M)
    if not section:
        sys.exit("CHANGELOG.md has no '## Unreleased' section")
    notes = "\n".join(line for line in (section.group(1).strip(), ALWAYS) if line)

    project = PROJECT.read_text(encoding="utf-8")
    current = re.search(r"<Version>(\d+)\.(\d+)\.(\d+)</Version>", project)
    if not current:
        sys.exit("<Version> not found in Estris.csproj")
    major, minor, patch = (int(part) for part in current.groups())
    if bump == "major":
        major, minor, patch = major + 1, 0, 0
    elif bump == "minor":
        minor, patch = minor + 1, 0
    else:
        patch += 1
    version = f"{major}.{minor}.{patch}"
    PROJECT.write_text(project[:current.start()] + f"<Version>{version}</Version>" + project[current.end():], encoding="utf-8")

    today = datetime.date.today().isoformat()
    changelog = (changelog[:section.start()] + "## Unreleased\n\n" + f"## {version} - {today}\n\n"
                 + notes + "\n\n" + changelog[section.end():].lstrip("\n"))
    CHANGELOG.write_text(changelog.rstrip("\n") + "\n", encoding="utf-8")

    notes_file.parent.mkdir(parents=True, exist_ok=True)
    notes_file.write_text(notes + "\n", encoding="utf-8")
    print(f"version={version}")


if __name__ == "__main__":
    main()
