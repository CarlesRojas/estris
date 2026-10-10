#!/usr/bin/env python3
"""Checks that every user-facing string in Sources/ is translated in every language.

Finds text the app shows (literals in SwiftUI views, String(localized:), tab and section
names) and reports any missing from Resources/Localization/<language>.lproj/Localizable.strings,
plus keys a language has that English doesn't. Run it after changing any visible text:

    python3 scripts/check-localization.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
LOCALIZATION = ROOT / "Resources" / "Localization"

# Calls whose first string literal is shown translated.
CALLS = [
    "String(localized: ", "Text(", "Button(", "Label(", "Toggle(", "Picker(", "Section(",
    "TextField(", "Stepper(", "LabeledContent(", "ColorPicker(", ".help(", ".alert(", "WarningLabel(",
    ".confirmationDialog(", "placeholder(", "slider(", "picker(", "summary: ", "prompt: ", "reason: ", "without: ",
]
# Enums whose raw values are shown translated.
ENUMS = ["Tab", "Section", "Phase"]


def read_literal(text, start):
    """The Swift string literal starting at text[start] == '"', and where it ends."""
    i, depth, out = start + 1, 0, []
    while i < len(text):
        c = text[i]
        if c == "\\" and text[i + 1] == "(":
            # An interpolation: skip it, nested strings and parentheses included.
            j, level = i + 2, 1
            while level:
                if text[j] == '"':
                    _, j = read_literal(text, j)
                    continue
                level += {"(": 1, ")": -1}.get(text[j], 0)
                j += 1
            out.append("{}")
            i = j
            continue
        if c == "\\":
            out.append(text[i:i + 2])
            i += 2
            continue
        if c == '"':
            return "".join(out), i + 1
        out.append(c)
        i += 1
    raise ValueError("unterminated string")


def normalize(key):
    """Interpolations and format specifiers compare equal."""
    key = re.sub(r"%(\d+\$)?(lld|ld|d|@|lf|f)", "{}", key)
    key = key.replace("\\u{201C}", "“").replace("\\u{201D}", "”").replace('\\"', '"')
    return key


def used_keys():
    keys = {}
    for path in SOURCES.rglob("*.swift"):
        text = path.read_text()
        for call in CALLS:
            for match in re.finditer(re.escape(call), text):
                at = match.end()
                if text.startswith("verbatim:", at):
                    continue
                # The call's first argument, if it is a literal or a ternary of literals.
                for literal in re.finditer(r'"', text[at:at + 400]):
                    pos = at + literal.start()
                    before = text[at:pos]
                    if before.strip() not in ("", "isRecording ?") and not re.fullmatch(r"[^\"]*\? ?", before):
                        break
                    value, _ = read_literal(text, pos)
                    if re.search(r"[A-Za-z]{2}", value):
                        keys.setdefault(normalize(value), f"{path.relative_to(ROOT)}")
                    break
        for name in ENUMS:
            for enum in re.finditer(r"enum " + name + r"\b[^{]*\{(.*?)\n    \}|enum " + name + r"\b[^{]*\{(.*?)\n\}", text, re.S):
                body = enum.group(1) or enum.group(2) or ""
                for raw in re.finditer(r'case \w+ = "([^"]+)"', body):
                    keys.setdefault(normalize(raw.group(1)), f"{path.relative_to(ROOT)}")
    return keys


def strings_file(path):
    entries = {}
    for match in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', path.read_text(), re.M):
        entries[match.group(1)] = match.group(2)
    return entries


def main():
    languages = sorted(p.name.removesuffix(".lproj") for p in LOCALIZATION.glob("*.lproj"))
    tables = {lang: strings_file(LOCALIZATION / f"{lang}.lproj" / "Localizable.strings") for lang in languages}
    english = tables.get("en", {})
    english_normalized = {normalize(k) for k in english}
    problems = 0
    for key, where in sorted(used_keys().items()):
        if key not in english_normalized:
            print(f"missing in en: {key!r} ({where})")
            problems += 1
    for lang, table in tables.items():
        for key in sorted(set(english) - set(table)):
            print(f"missing in {lang}: {key!r}")
            problems += 1
        for key in sorted(set(table) - set(english)):
            print(f"not in en, remove from {lang}: {key!r}")
            problems += 1
    print(f"{len(english)} strings, {len(languages)} languages, {problems} problems")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
