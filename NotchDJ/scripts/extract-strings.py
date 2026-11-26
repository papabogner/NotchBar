#!/usr/bin/env python3
"""Lists the localizable strings in Sources/ and checks them against Resources/*.lproj.

Usage: scripts/extract-strings.py [--check]

Finds String(localized: "...") and the SwiftUI initializers that take a LocalizedStringKey
literal (Text, Button, Toggle, Picker, Section, Link, Label, LabeledContent, .help). An
interpolation becomes %lld when the expression looks like an Int and %@ otherwise, the same
keys Swift generates. Keep INT_HINTS in sync when you add an integer interpolation.

With --check, exits 1 when a key is missing from a Localizable.strings file, or a file has a
key the code no longer uses.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
RESOURCES = ROOT / "Resources"

# Interpolated expressions that are integers.
INT_HINTS = ("rawValue + 1", ".count", "level")

CALLS = re.compile(
    r'(?:String\(localized:\s*|(?<![\w.])(?:SwiftUI\.)?(?:Text|Button|Toggle|Picker|Section|Link|Label|LabeledContent)\(\s*|\.help\(\s*)"((?:[^"\\]|\\.)*)"'
)
INTERPOLATION = re.compile(r'\\\(((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)\)')


def key_for(literal: str) -> str:
    def replace(match: re.Match) -> str:
        expression = match.group(1)
        return "%lld" if any(hint in expression for hint in INT_HINTS) else "%@"
    key = INTERPOLATION.sub(replace, literal)
    return key.replace('\\"', '"')


def code_keys() -> dict:
    keys = {}
    for path in sorted(SOURCES.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for match in CALLS.finditer(text):
            literal = match.group(1)
            if not re.search(r"[A-Za-z]", literal):
                continue
            key = key_for(literal)
            line = text.count("\n", 0, match.start()) + 1
            keys.setdefault(key, []).append(f"{path.relative_to(ROOT)}:{line}")
    return keys


ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')


def table(path: pathlib.Path) -> dict:
    entries = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("/*") or line.startswith("//") or line.startswith("*"):
            continue
        match = ENTRY.match(line)
        if not match:
            raise SystemExit(f"{path}:{number}: can't read: {line}")
        key = match.group(1).replace('\\"', '"').replace("\\n", "\n")
        entries[key] = match.group(2)
    return entries


def placeholders(value: str) -> list:
    return re.findall(r"%(?:\d+\$)?(?:lld|@|d|ld)", value)


def main() -> int:
    keys = code_keys()
    if "--check" not in sys.argv:
        for key, places in sorted(keys.items()):
            print(f"{key!r}  ({places[0]}{' +' + str(len(places) - 1) if len(places) > 1 else ''})")
        return 0
    failed = False
    for strings in sorted(RESOURCES.glob("*.lproj/Localizable.strings")):
        entries = table(strings)
        for key in sorted(set(keys) - set(entries)):
            print(f"{strings.parent.name}: missing {key!r}  ({keys[key][0]})")
            failed = True
        for key in sorted(set(entries) - set(keys)):
            print(f"{strings.parent.name}: unused {key!r}")
            failed = True
        for key, value in entries.items():
            if sorted(placeholders(key)) != sorted(placeholders(value)):
                print(f"{strings.parent.name}: placeholders differ in {key!r}")
                failed = True
    print("strings: problems found" if failed else f"strings: {len(keys)} keys, all present")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
