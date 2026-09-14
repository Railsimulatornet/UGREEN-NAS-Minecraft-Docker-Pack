#!/usr/bin/env python3
"""Targeted Bedrock add-on compatibility fixes for the temporary staging tree."""

from __future__ import annotations

import json
import os
import re
import shutil
import sys
from pathlib import Path

BACKPACK_BP_UUID = "5772ca6e-ea65-417d-be87-c3e8203d941c"
FARAMIR_BP_UUID = "812280d1-2a0d-463d-a5ff-340fa6c32e86"
VCS_DIRS = {".git", ".svn", ".hg"}


def strip_json_comments(text: str) -> str:
    if text.startswith("\ufeff"):
        text = text.lstrip("\ufeff")
    out = []
    i = 0
    in_string = escaped = in_line = in_block = False

    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""

        if in_line:
            if ch in "\r\n":
                in_line = False
                out.append(ch)
            i += 1
            continue

        if in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                i += 2
            else:
                i += 1
            continue

        if in_string:
            out.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            i += 1
            continue

        if ch == '"':
            in_string = True
            out.append(ch)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            in_line = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block = True
            i += 2
            continue

        out.append(ch)
        i += 1

    return "".join(out)


def load_manifest(path: Path):
    try:
        text = path.read_text(encoding="utf-8-sig")
        text = strip_json_comments(text)
        text = re.sub(r",\s*([}\]])", r"\1", text)
        data = json.loads(text)
        return data if isinstance(data, dict) else None
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None


def code_without_js_comments(text: str) -> str:
    out = []
    i = 0
    quote = None
    escaped = in_line = in_block = False

    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""

        if in_line:
            if ch in "\r\n":
                in_line = False
                out.append(ch)
            else:
                out.append(" ")
            i += 1
            continue

        if in_block:
            if ch == "*" and nxt == "/":
                out.extend("  ")
                in_block = False
                i += 2
            else:
                out.append("\n" if ch == "\n" else " ")
                i += 1
            continue

        if quote is not None:
            out.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = None
            i += 1
            continue

        if ch in ('"', "'", chr(96)):
            quote = ch
            out.append(ch)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            out.extend("  ")
            in_line = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            out.extend("  ")
            in_block = True
            i += 2
            continue

        out.append(ch)
        i += 1

    return "".join(out)


def patch_backpacks_type_only_imports(pack_root: Path):
    import_re = re.compile(
        r'import\s*\{(?P<body>[^}]*)\}\s*from\s*(?P<q>["\'])@minecraft/server(?P=q)\s*;?'
    )
    changed = []

    for path in pack_root.rglob("*.js"):
        try:
            text = path.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError):
            continue

        original = text
        for match in reversed(list(import_re.finditer(text))):
            specs = [item.strip() for item in match.group("body").split(",") if item.strip()]
            remainder = text[:match.start()] + text[match.end():]
            executable = code_without_js_comments(remainder)
            kept = []

            for spec in specs:
                local_name = re.split(r"\s+as\s+", spec, maxsplit=1)[-1].strip()
                if re.search(rf"\b{re.escape(local_name)}\b", executable):
                    kept.append(spec)

            if len(kept) == len(specs):
                continue

            replacement = (
                'import { ' + ", ".join(kept) + ' } from "@minecraft/server";'
                if kept else ""
            )
            text = text[:match.start()] + replacement + text[match.end():]

        if text != original:
            path.write_text(text, encoding="utf-8", newline="")
            changed.append(path)

    return changed


def normalize_faramir_materials(pack_root: Path):
    render_re = re.compile(r'("render_method"\s*:\s*")([^"\r\n]+)(")')
    rank = {
        "opaque": 0,
        "double_sided": 1,
        "alpha_test_single_sided_to_opaque": 2,
        "alpha_test_single_sided": 3,
        "alpha_test_to_opaque": 4,
        "alpha_test": 5,
        "blend_to_opaque": 6,
        "blend": 7,
    }
    changed = []
    blocks = pack_root / "blocks"
    if not blocks.is_dir():
        return changed

    for path in blocks.rglob("*.json"):
        try:
            text = path.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError):
            continue

        methods = [m.group(2) for m in render_re.finditer(text)]
        unique = set(methods)
        if len(unique) <= 1 or not unique.issubset(rank):
            continue

        target = max(unique, key=rank.__getitem__)
        patched = render_re.sub(lambda m: m.group(1) + target + m.group(3), text)
        if patched != text:
            path.write_text(patched, encoding="utf-8", newline="")
            changed.append((path, tuple(sorted(unique)), target))

    return changed


def remove_vcs_metadata(root: Path):
    removed = []
    for dirpath, dirnames, _filenames in os.walk(root, topdown=True):
        for name in list(dirnames):
            if name not in VCS_DIRS:
                continue
            path = Path(dirpath) / name
            shutil.rmtree(path, ignore_errors=True)
            removed.append(path)
            dirnames.remove(name)
    return removed


def main(root: Path) -> int:
    if not root.is_dir():
        print(f"[compat][error] staging directory not found: {root}", file=sys.stderr)
        return 2

    pack_roots = []
    for manifest in root.rglob("manifest.json"):
        if any(part in VCS_DIRS for part in manifest.parts):
            continue
        data = load_manifest(manifest)
        if not data:
            continue
        uuid = str((data.get("header") or {}).get("uuid") or "").lower()
        if uuid:
            pack_roots.append((uuid, manifest.parent))

    backpack_changes = []
    faramir_changes = []
    for uuid, pack_root in pack_roots:
        if uuid == BACKPACK_BP_UUID:
            backpack_changes.extend(patch_backpacks_type_only_imports(pack_root))
        elif uuid == FARAMIR_BP_UUID:
            faramir_changes.extend(normalize_faramir_materials(pack_root))

    vcs_removed = remove_vcs_metadata(root)

    if backpack_changes or faramir_changes or vcs_removed:
        print(
            "[compat] applied: "
            f"backpacks_js={len(set(backpack_changes))}, "
            f"faramir_materials={len(faramir_changes)}, "
            f"vcs_dirs_removed={len(vcs_removed)}"
        )
        for path in sorted(set(backpack_changes)):
            print(f"[compat] Backpacks JS: {path.relative_to(root)}")
        for path, old, target in faramir_changes:
            print(
                f"[compat] Faramir material: {path.relative_to(root)} "
                f"{','.join(old)} -> {target}"
            )
        for path in vcs_removed:
            print(f"[compat] removed metadata: {path.relative_to(root)}")
    else:
        print("[compat] no compatibility changes required")

    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <staging-dir>", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(Path(sys.argv[1])))
