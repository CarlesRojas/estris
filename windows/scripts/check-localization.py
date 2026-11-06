#!/usr/bin/env python3
"""Checks that all the text the Windows app shows is translated in every language.

Finds T("...") and the utilities' Title in src/Estris and reports any missing from
src/Estris/Localization/<language>/*.strings, keyed by the English text as on the Mac.
English needs no file: the key is the text. Run it after changing any visible text:

    python windows/scripts/check-localization.py

With --from-mac, keys missing here that the Mac app has translated are first copied into
Localization/<language>/App.strings, so shared text is only translated once.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "src" / "Estris"
LOCALIZATION = ROOT / "Localization"
MAC = ROOT.parent.parent.parent / "macos" / "Resources" / "Localization"
LANGUAGES = ["es", "fr", "pt-BR", "de", "it", "ca"]
USED = re.compile(r'(?<![A-Za-z.])T\(\s*\$?"((?:[^"\\]|\\.)*)"')
TITLE = re.compile(r'public string Title => "((?:[^"\\]|\\.)*)"')
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', re.M)


def used_keys():
    keys = set()
    for path in ROOT.rglob("*.cs"):
        if "obj" in path.parts or "bin" in path.parts:
            continue
        # Doc comments show examples, not text.
        text = "
".join(l for l in path.read_text(encoding="utf-8").splitlines() if not l.lstrip().startswith("//"))
        keys.update(USED.findall(text))
        keys.update(TITLE.findall(text))
    return keys


def table(folder):
    entries = {}
    for path in folder.glob("*.strings"):
        entries.update(ENTRY.findall(path.read_text(encoding="utf-8")))
    return entries


def fill_from_mac(keys):
    for language in LANGUAGES:
        mac = dict(ENTRY.findall((MAC / f"{language}.lproj" / "Localizable.strings").read_text(encoding="utf-8")))
        folder = LOCALIZATION / language
        folder.mkdir(parents=True, exist_ok=True)
        have = table(folder)
        new = sorted(k for k in keys if k in mac and k not in have)
        if new:
            with (folder / "App.strings").open("a", encoding="utf-8", newline="\n") as file:
                file.writelines(f'"{k}" = "{mac[k]}";\n' for k in new)


def main():
    keys = used_keys()
    if "--from-mac" in sys.argv:
        fill_from_mac(keys)
    problems = 0
    for language in LANGUAGES:
        have = table(LOCALIZATION / language)
        for key in sorted(keys - have.keys()):
            print(f"{language}: missing {key!r}")
            problems += 1
    print(f"{len(keys)} strings, {len(LANGUAGES) + 1} languages, {problems} problems")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
