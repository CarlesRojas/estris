#!/usr/bin/env python3
"""Prepares a release: bumps the version in Info.plist and turns the changelog's Unreleased
section into the new version's. Used by the Release workflow.

    python3 scripts/release.py patch|minor|major NOTES_FILE

Writes the release notes (the Unreleased entries, then a line every release has) to NOTES_FILE
and prints `version=X.Y.Z` for the workflow. Unreleased may be empty.
"""
import datetime
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLIST = ROOT / "Resources/Info.plist"
CHANGELOG = ROOT / "CHANGELOG.md"
# Last in every release's notes, even when nothing else is.
ALWAYS = "- Performance improvements and bug fixes."


def plist_value(text, key):
    match = re.search(rf"<key>{key}</key>\s*<string>([^<]*)</string>", text)
    if not match:
        sys.exit(f"{key} not found in Info.plist")
    return match


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("patch", "minor", "major"):
        sys.exit(__doc__)
    bump, notes_file = sys.argv[1], Path(sys.argv[2])

    changelog = CHANGELOG.read_text()
    section = re.search(r"^## Unreleased\n(.*?)(?=^## |\Z)", changelog, re.S | re.M)
    if not section:
        sys.exit("CHANGELOG.md has no '## Unreleased' section")
    notes = "\n".join(line for line in (section.group(1).strip(), ALWAYS) if line)

    plist = PLIST.read_text()
    current = plist_value(plist, "CFBundleShortVersionString")
    major, minor, patch = (int(part) for part in current.group(1).split("."))
    if bump == "major":
        major, minor, patch = major + 1, 0, 0
    elif bump == "minor":
        minor, patch = minor + 1, 0
    else:
        patch += 1
    version = f"{major}.{minor}.{patch}"
    plist = plist[:current.start(1)] + version + plist[current.end(1):]
    build = plist_value(plist, "CFBundleVersion")
    plist = plist[:build.start(1)] + str(int(build.group(1)) + 1) + plist[build.end(1):]
    PLIST.write_text(plist)

    today = datetime.date.today().isoformat()
    changelog = (changelog[:section.start()] + "## Unreleased\n\n" + f"## {version} - {today}\n\n"
                 + notes + "\n\n" + changelog[section.end():].lstrip("\n"))
    CHANGELOG.write_text(changelog.rstrip("\n") + "\n")

    notes_file.parent.mkdir(parents=True, exist_ok=True)
    notes_file.write_text(notes + "\n")
    print(f"version={version}")


if __name__ == "__main__":
    main()
