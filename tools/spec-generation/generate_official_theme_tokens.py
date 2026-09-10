#!/usr/bin/env python3
"""Extract DeepSeek Harness design-token semantics from the upstream CSS."""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

THEME_PATH = Path("packages/client/ui-theme/src/styles/design-platform.css")
DECLARATION = re.compile(r"^\s*(--dsw-[\w-]+)\s*:\s*([^;]+);\s*$")
VAR = re.compile(r"var\((--dsw-[\w-]+)\)")
RGB = re.compile(r"^rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$")
RGBA = re.compile(r"^rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([0-9.]+)\s*\)$")


@dataclass(frozen=True)
class Declaration:
    css_name: str
    raw_value: str
    scheme: str


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", type=Path, required=True)
    parser.add_argument("--json-output", type=Path, required=True)
    parser.add_argument("--swift-output", type=Path, required=True)
    return parser.parse_args()


def parse(root: Path) -> tuple[dict[str, Declaration], dict[str, Declaration]]:
    lines = (root / THEME_PATH).read_text(encoding="utf-8").splitlines()
    light: dict[str, Declaration] = {}
    dark: dict[str, Declaration] = {}
    scheme = "light"
    for line in lines:
        if "body[data-ds-dark-theme]" in line:
            scheme = "dark"
        elif line.strip() == "body {":
            scheme = "light"
        match = DECLARATION.match(line)
        if match is None:
            continue
        declaration = Declaration(match.group(1), match.group(2).strip(), scheme)
        (dark if scheme == "dark" else light)[declaration.css_name] = declaration
    if not light or not dark:
        raise ValueError("expected light and dark --dsw-* declarations")
    return light, dark


def rgba(value: str) -> dict[str, float] | None:
    rgb = RGB.fullmatch(value)
    if rgb:
        return {
            "red": int(rgb.group(1)) / 255,
            "green": int(rgb.group(2)) / 255,
            "blue": int(rgb.group(3)) / 255,
            "alpha": 1,
        }
    rgba_match = RGBA.fullmatch(value)
    if rgba_match:
        return {
            "red": int(rgba_match.group(1)) / 255,
            "green": int(rgba_match.group(2)) / 255,
            "blue": int(rgba_match.group(3)) / 255,
            "alpha": float(rgba_match.group(4)),
        }
    return None


def resolve(name: str, declarations: dict[str, Declaration], stack: tuple[str, ...] = ()) -> tuple[str, dict[str, float] | None]:
    if name in stack:
        raise ValueError("cyclic CSS variable: " + " -> ".join((*stack, name)))
    declaration = declarations.get(name)
    if declaration is None:
        raise ValueError(f"unresolved CSS variable {name}")
    variable = VAR.fullmatch(declaration.raw_value)
    if variable:
        return resolve(variable.group(1), declarations, (*stack, name))
    return declaration.raw_value, rgba(declaration.raw_value)


def swift_identifier(css_name: str) -> str:
    words = css_name.removeprefix("--dsw-").replace("-", " ").split()
    return words[0] + "".join(word.capitalize() for word in words[1:])


def swift_rgba(value: dict[str, float]) -> str:
    return (
        "OfficialRGBA("
        f"red: {repr(value['red'])}, "
        f"green: {repr(value['green'])}, "
        f"blue: {repr(value['blue'])}, "
        f"alpha: {repr(value['alpha'])}"
        ")"
    )


def swift_source(tokens: list[dict[str, object]]) -> str:
    literals: list[str] = []
    properties: list[str] = []
    for token in tokens:
        name = str(token["cssName"])
        identifier = swift_identifier(name)
        light = token["light"]["resolvedRGBA"]
        dark = token["dark"]["resolvedRGBA"]
        if light is None or dark is None:
            continue
        literals.append(
            f'        "{name}": OfficialColorToken(cssName: "{name}", light: {swift_rgba(light)}, dark: {swift_rgba(dark)})'
        )
        properties.append(f'    static let {identifier} = value("{name}")')
    values = ",\n".join(literals)
    accessors = "\n".join(properties)
    return f'''// Generated from upstream design-platform.css; do not edit.\nimport AppKit\nimport SwiftUI\n\nstruct OfficialRGBA: Hashable, Sendable {{\n    let red: Double\n    let green: Double\n    let blue: Double\n    let alpha: Double\n\n    func color(for scheme: ColorScheme) -> Color {{\n        Color(red: red, green: green, blue: blue, opacity: alpha)\n    }}\n}}\n\nstruct OfficialColorToken: Hashable, Sendable {{\n    let cssName: String\n    let light: OfficialRGBA\n    let dark: OfficialRGBA\n\n    func color(for scheme: ColorScheme) -> Color {{\n        (scheme == .dark ? dark : light).color(for: scheme)\n    }}\n\n    var lightColor: Color {{ light.color(for: .light) }}\n    var darkColor: Color {{ dark.color(for: .dark) }}\n\n    var adaptiveColor: Color {{\n        Color(NSColor(name: nil) {{ appearance in\n            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua\n            let value = isDark ? dark : light\n            return NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.alpha)\n        }})\n    }}\n}}\n\nextension OfficialUISpec {{\n    enum Theme {{\n        static let colorTokens: [String: OfficialColorToken] = [\n{values}\n        ]\n\n        static func value(_ cssName: String) -> OfficialColorToken {{\n            guard let token = colorTokens[cssName] else {{\n                preconditionFailure("Unknown official color token: \\(cssName)")\n            }}\n            return token\n        }}\n\n{accessors}\n    }}\n}}\n'''


def main() -> None:
    args = arguments()
    light, dark = parse(args.official_root.resolve())
    names = sorted(set(light) | set(dark))
    tokens: list[dict[str, object]] = []
    for name in names:
        light_declaration = light.get(name)
        dark_declaration = dark.get(name, light_declaration)
        if light_declaration is None or dark_declaration is None:
            raise ValueError(f"missing color token scheme for {name}")
        light_resolved, light_rgba = resolve(name, light)
        dark_resolved, dark_rgba = resolve(name, {**light, **dark})
        tokens.append({
            "cssName": name,
            "light": {
                "rawValue": light_declaration.raw_value,
                "resolvedValue": light_resolved,
                "resolvedRGBA": light_rgba,
            },
            "dark": {
                "rawValue": dark_declaration.raw_value,
                "resolvedValue": dark_resolved,
                "resolvedRGBA": dark_rgba,
            },
        })
    document = {"schemaVersion": 1, "tokens": tokens}
    args.json_output.parent.mkdir(parents=True, exist_ok=True)
    args.json_output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    args.swift_output.parent.mkdir(parents=True, exist_ok=True)
    args.swift_output.write_text(swift_source(tokens), encoding="utf-8")
    print(f"Generated {len(tokens)} official color tokens from {THEME_PATH}.")


if __name__ == "__main__":
    main()
