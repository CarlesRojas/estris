#!/usr/bin/env python3
"""Writes the appcast Sparkle reads to find updates: one item, the release being published.
Used by the Release workflow, after the disk image is signed for updates.

    python3 scripts/make-appcast.py VERSION SIGNATURE NOTES_FILE > build/appcast.xml

SIGNATURE is what Sparkle's sign_update prints for the disk image
(`sparkle:edSignature="…" length="…"`). The notes are the changelog's entries, in Markdown.
"""
import html
import re
import sys
from email.utils import formatdate
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "https://github.com/CarlesRojas/estris"


def plist_value(key):
    text = (ROOT / "Resources/Info.plist").read_text()
    return re.search(rf"<key>{key}</key>\s*<string>([^<]*)</string>", text).group(1)


def notes_html(markdown):
    """The changelog's bullet list as HTML, nested items included, with bold kept."""
    out, depth = [], 0
    for line in markdown.splitlines():
        match = re.match(r"(\s*)- (.*)", line)
        if not match:
            continue
        level = len(match.group(1)) // 2 + 1
        while depth < level:
            out.append("<ul>")
            depth += 1
        while depth > level:
            out.append("</ul>")
            depth -= 1
        text = html.escape(match.group(2))
        text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
        text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
        out.append(f"<li>{text}</li>")
    out.extend(["</ul>"] * depth)
    return "\n".join(out)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    version, signature, notes_file = sys.argv[1], sys.argv[2].strip(), Path(sys.argv[3])
    if not re.fullmatch(r'sparkle:edSignature="[^"]+" length="\d+"', signature):
        sys.exit(f"Unexpected signature: {signature}")
    build = plist_value("CFBundleVersion")
    minimum = plist_value("LSMinimumSystemVersion")
    notes = notes_html(notes_file.read_text())
    url = f"{REPO}/releases/download/v{version}/Estris.dmg"
    print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Estris</title>
    <link>{REPO}</link>
    <item>
      <title>Estris {version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{minimum}</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{url}" type="application/octet-stream" {signature}/>
    </item>
  </channel>
</rss>""")


if __name__ == "__main__":
    main()
