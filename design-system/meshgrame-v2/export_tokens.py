"""Export the MeshGrame V2 DTCG tokens to CSS and Dart."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def color_channels(value):
    return [round(part * 255) for part in value["components"]], round(value.get("alpha", 1) * 255)


def css_value(kind, value):
    if kind == "color":
        rgb, alpha = color_channels(value)
        return "#" + "".join(f"{part:02x}" for part in rgb + ([alpha] if alpha < 255 else []))
    if kind == "fontFamily":
        return ", ".join(value)
    return f"{value['value']}{value['unit']}"


def dart_value(kind, value):
    if kind == "color":
        rgb, alpha = color_channels(value)
        return f"0x{alpha:02X}" + "".join(f"{part:02X}" for part in rgb)
    if kind == "duration":
        return str(value["value"])
    return f"{float(value['value']):.1f}"


def dart_name(name):
    first, *rest = re.split(r"[-.]", name)
    return first + "".join(part[:1].upper() + part[1:] for part in rest)


def flatten(group, prefix="", inherited_type=None):
    for name, value in group.items():
        if name.startswith("$"):
            continue
        path = f"{prefix}-{name}" if prefix else name
        token_type = value.get("$type", group.get("$type", inherited_type))
        if "$value" in value:
            yield path, token_type, value["$value"]
        else:
            yield from flatten(value, path, token_type)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify exports without rewriting them")
    check = parser.parse_args().check
    source = json.loads((ROOT / "tokens.json").read_text())
    common = list(flatten(source["foundation"]))
    palettes = {mode: list(flatten(source["color"][mode], "color", "color")) for mode in ("light", "dark")}
    css = ["/* Generated from tokens.json by export_tokens.py. */"]
    for mode, tokens in palettes.items():
        selector = ':root[data-design="v2"]'
        if mode == "dark":
            selector += '[data-theme="dark"]'
        css.append(selector + " {")
        for name, kind, value in (common if mode == "light" else []) + tokens:
            # Convert type tokens to rem so browser text scaling affects them.
            css_token = f"{value['value'] / 16:g}rem" if name.startswith("type-") else css_value(kind, value)
            css.append(f"  --mg-{name}: {css_token};")
        css.append("}")
    # Dart uses ARGB integers. The app can wrap them in const Color().
    dart = ["// Generated from tokens.json by export_tokens.py.", ""]
    for class_name, tokens in [("MeshGrameV2", common), *[
        ("MeshGrameV2" + mode.title(), tokens) for mode, tokens in palettes.items()
    ]]:
        dart.append(f"abstract final class {class_name} {{")
        for name, kind, value in tokens:
            if kind == "fontFamily":
                continue  # Flutter uses the native platform font.
            name = name.removeprefix("color-")
            dart.append(f"  static const {dart_name(name)} = {dart_value(kind, value)};")
        dart.extend(["}", ""])

    for filename, lines in [("tokens.css", css), ("tokens.dart", dart)]:
        target = ROOT / filename
        result = "\n".join(lines).rstrip() + "\n"
        if check:
            if target.read_text() != result:
                raise SystemExit(f"Tokens out of date: {filename}")
        else:
            target.write_text(result)


if __name__ == "__main__":
    main()
