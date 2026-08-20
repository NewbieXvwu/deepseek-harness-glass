#!/usr/bin/env python3
"""Generate a provenance-preserving English/Chinese locale catalog from locked upstream TypeScript."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import re
import subprocess
from collections import defaultdict
from pathlib import Path


GENERATOR_NAME = "generate_official_locales.py"
GENERATOR_VERSION = "1.0.0"
EXPECTED_COMMIT = "141eb6fef83422698aef7a981029e843e8161534"
EXPORT = re.compile(r"^\s*export\s+const\s+(en|zh)\b[^=]*=\s*\{")
PROPERTY_START = re.compile(
    r"^\s*(?P<key>'(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\"|[A-Za-z_$][\w$]*)\s*:\s*(?P<expression>.*)$",
    re.DOTALL,
)
NAMED_CONSTANT = re.compile(r"^\s*const\s+(?P<name>[A-Za-z_$][\w$]*)\s*=\s*(?P<expression>.*?);?\s*$")
IDENTIFIER = re.compile(r"^[A-Za-z_$][\w$]*$")
STRING_LITERAL = re.compile(r"'(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\"|`(?:\\.|[^`])*`")
INTERPOLATION = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}")
ONBOARDING_COPY_IMPORT = re.compile(r"import\s+\{\s*WELCOME_NOTICE_COPY\s*\}\s+from\s+'(?P<path>[^']+)'" )


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    parser.add_argument("--json-output", type=Path, required=True)
    parser.add_argument("--swift-output", type=Path, required=True)
    return parser.parse_args()


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def locale_files(root: Path) -> list[Path]:
    paths = set(root.glob("packages/client/**/src/client/locales.ts"))
    paths.update(root.glob("packages/client/**/src/client/locale.ts"))
    paths.update(root.glob("packages/client/locale/src/locales/*.ts"))
    return sorted(path for path in paths if path.is_file())


def locale_source_files(root: Path) -> list[Path]:
    paths = set(locale_files(root))
    paths.add(root / "packages/client/ui-settings-models/src/onboarding-copy.ts")
    missing = [path for path in paths if not path.is_file()]
    if missing:
        raise ValueError("missing locale source input(s): " + ", ".join(map(str, missing)))
    return sorted(paths)


def source_input_revision(root: Path) -> str:
    accumulator = hashlib.sha256()
    for path in locale_source_files(root):
        accumulator.update(path.relative_to(root).as_posix().encode("utf-8"))
        accumulator.update(b"\0")
        accumulator.update(path.read_bytes())
    return "sha256:" + accumulator.hexdigest()


def namespace(root: Path, path: Path) -> str:
    relative = path.relative_to(root).as_posix()
    match = re.match(r"packages/client/([^/]+)/src/client/(?:locales|locale)\.ts$", relative)
    if match:
        return match.group(1)
    if relative.startswith("packages/client/locale/src/locales/"):
        return "locale"
    raise ValueError(f"unrecognized locale path: {relative}")


def decode_string(raw: str) -> str:
    if raw.startswith("`"):
        raw = repr(raw[1:-1])
    try:
        value = ast.literal_eval(raw)
    except (SyntaxError, ValueError) as error:
        raise ValueError(f"cannot decode TypeScript locale string {raw!r}: {error}") from error
    if not isinstance(value, str):
        raise ValueError(f"locale value is not a string: {raw!r}")
    return value


def decode_key(raw: str) -> str:
    return decode_string(raw) if raw[:1] in {"'", '"'} else raw


def decode_expression(expression: str, constants: dict[str, str] | None = None) -> str:
    """Accept a literal, literal concatenation, or a resolved named-copy reference."""
    expression = expression.strip()
    if expression.endswith(","):
        expression = expression[:-1]
    if constants is not None and expression in constants:
        return constants[expression]
    if IDENTIFIER.fullmatch(expression):
        raise ValueError(f"unresolved locale string constant: {expression}")
    tokens = list(STRING_LITERAL.finditer(expression))
    if not tokens:
        raise ValueError(f"locale expression has no string literal: {expression}")
    residue = STRING_LITERAL.sub("", expression)
    if re.sub(r"[\s+]", "", residue):
        raise ValueError(f"unsupported non-string locale expression: {expression}")
    return "".join(decode_string(match.group(0)) for match in tokens)


def plural_category(key: str) -> str | None:
    final = key.rsplit(".", 1)[-1]
    return final if final in {"zero", "one", "two", "few", "many", "other"} else None


def imported_copy_constants(path: Path) -> dict[str, str]:
    source = path.read_text(encoding="utf-8")
    constants: dict[str, str] = {}
    for language in ("en", "zh"):
        for field in ("title", "body", "continueLabel"):
            pattern = re.compile(
                rf"{language}\s*:\s*\{{.*?\b{field}\s*:\s*(?P<value>'(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\"|`(?:\\.|[^`])*`)",
                re.DOTALL,
            )
            match = pattern.search(source)
            if match is None:
                raise ValueError(f"missing WELCOME_NOTICE_COPY.{language}.{field} in {path}")
            constants[f"WELCOME_NOTICE_COPY.{language}.{field}"] = decode_string(match.group("value"))
    return constants


def parse_file(root: Path, path: Path, commit: str) -> list[dict[str, object]]:
    source_text = path.read_text(encoding="utf-8")
    lines = source_text.splitlines()
    constants: dict[str, str] = {}
    copy_import = ONBOARDING_COPY_IMPORT.search(source_text)
    if copy_import:
        copied_path = (path.parent / copy_import.group("path")).resolve()
        constants.update(imported_copy_constants(copied_path))
    for constant_line in lines:
        constant = NAMED_CONSTANT.match(constant_line)
        if constant:
            try:
                constants[constant.group("name")] = decode_expression(constant.group("expression"), constants)
            except ValueError:
                # Locale modules may also define non-copy conditional helpers.
                # They are deliberately not accepted as locale values; a locale
                # entry that references one still fails as unresolved below.
                continue
    found: list[dict[str, object]] = []
    active_language: str | None = None
    active_start = 0
    pending: list[str] = []
    pending_line = 0

    def flush_pending() -> None:
        nonlocal pending
        statement = "\n".join(pending)
        match = PROPERTY_START.match(statement)
        if match is None:
            raise ValueError(f"unsupported locale property at {path.relative_to(root)}:{pending_line}: {statement}")
        assert active_language is not None
        key = decode_key(match.group("key"))
        value = decode_expression(match.group("expression"), constants)
        found.append({
            "id": f"{namespace(root, path)}.{key}",
            "namespace": namespace(root, path),
            "key": key,
            "language": active_language,
            "value": value,
            "interpolationParameters": sorted(set(INTERPOLATION.findall(value))),
            "pluralCategory": plural_category(key),
            "source": {
                "path": path.relative_to(root).as_posix(),
                "line": pending_line,
                "commit": commit,
            },
            "exportStartedAtLine": active_start,
        })
        pending = []

    for line_number, line in enumerate(lines, start=1):
        declaration = EXPORT.match(line)
        if declaration:
            if active_language is not None:
                raise ValueError(f"nested locale export at {path.relative_to(root)}:{line_number}")
            active_language = declaration.group(1)
            active_start = line_number
            continue
        if active_language is None:
            continue
        if line.lstrip().startswith("}"):
            if pending:
                flush_pending()
            active_language = None
            continue
        stripped = line.strip()
        if not pending and (not stripped or stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*")):
            continue
        if not pending:
            pending_line = line_number
        pending.append(line)
        # All supported official values are literal or literal concatenation and
        # finish with a comma. Keep multiline `+` chains intact until then.
        if stripped.endswith(","):
            flush_pending()
    if active_language is not None:
        raise ValueError(f"unterminated locale export in {path.relative_to(root)}")
    return found


def revision(entries: list[dict[str, object]]) -> str:
    serial = json.dumps(entries, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return "sha256:" + hashlib.sha256(serial.encode("utf-8")).hexdigest()


def swift_source(entries: list[dict[str, object]], commit: str, locale_revision: str, source_input: str) -> str:
    values = {
        f"{entry['language']}|{entry['id']}": str(entry["value"])
        for entry in entries
    }
    body = ",\n".join(
        f"        {json.dumps(key, ensure_ascii=False)}: {json.dumps(value, ensure_ascii=False)}"
        for key, value in sorted(values.items())
    )
    return f'''// Generated by {GENERATOR_NAME} {GENERATOR_VERSION}; do not edit.\nimport Foundation\n\nextension OfficialUISpec {{\n    enum LocaleCatalog {{\n        static let sourceCommit = "{commit}"\n        static let revision = "{locale_revision}"\n        static let sourceInputRevision = "{source_input}"\n        static let supportedLanguages: Set<String> = ["en", "zh"]\n        static let values: [String: String] = [\n{body}\n        ]\n\n        static func contains(namespace: String, key: String, language: String) -> Bool {{\n            values["\\(language)|\\(namespace).\\(key)"] != nil\n        }}\n\n        static func value(namespace: String, key: String, language: String) -> String? {{\n            values["\\(language)|\\(namespace).\\(key)"]\n        }}\n    }}\n}}\n'''


def main() -> None:
    args = arguments()
    root = args.official_root.resolve()
    commit = git(root, "rev-parse", "HEAD")
    if commit != EXPECTED_COMMIT:
        raise SystemExit(f"official root must be {EXPECTED_COMMIT}, got {commit}")
    entries: list[dict[str, object]] = []
    for path in locale_files(root):
        entries.extend(parse_file(root, path, commit))
    if not entries:
        raise SystemExit("no locale entries found")
    entries.sort(key=lambda entry: (str(entry["namespace"]), str(entry["key"]), str(entry["language"])))
    unique = {(str(entry["id"]), str(entry["language"])) for entry in entries}
    if len(unique) != len(entries):
        raise SystemExit("duplicate namespace/key/language locale entry")
    languages = {str(entry["language"]) for entry in entries}
    if not {"en", "zh"}.issubset(languages):
        raise SystemExit("generated locale catalog must contain English and Chinese")
    by_key: dict[str, set[str]] = defaultdict(set)
    for entry in entries:
        by_key[str(entry["id"])].add(str(entry["language"]))
    incomplete = sorted(key for key, values in by_key.items() if not {"en", "zh"}.issubset(values))
    if incomplete:
        raise SystemExit("locale keys missing en/zh translation: " + ", ".join(incomplete[:20]))
    locale_revision = revision(entries)
    source_input = source_input_revision(root)
    metadata = {
        "schemaVersion": 1,
        "sourceCommit": commit,
        "localeRevision": locale_revision,
        "sourceInputRevision": source_input,
        "generatedAt": git(root, "show", "-s", "--format=%cI", commit),
        "generator": {"name": GENERATOR_NAME, "version": GENERATOR_VERSION},
        "languages": sorted(languages),
        "entries": entries,
    }
    args.json_output.parent.mkdir(parents=True, exist_ok=True)
    args.json_output.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    args.swift_output.parent.mkdir(parents=True, exist_ok=True)
    args.swift_output.write_text(swift_source(entries, commit, locale_revision, source_input), encoding="utf-8")
    print(f"Generated {len(entries)} locale entries across {len(by_key)} keys from {len(locale_files(root))} files.")


if __name__ == "__main__":
    main()
