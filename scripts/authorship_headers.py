#!/usr/bin/env python3
# RSS2 — Agregador multilingüe de noticias RSS
# Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
# SPDX-License-Identifier: MIT
"""Añade o verifica la cabecera de autoría de Dinámicas Electrónicas.

Uso:
    python3 scripts/authorship_headers.py apply   # escribe las cabeceras
    python3 scripts/authorship_headers.py check   # falla si falta alguna

El script es idempotente: los ficheros que ya mencionan a Dinámicas
Electrónicas en sus primeras líneas no se tocan.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

OWNER = "Dinámicas Electrónicas"
EMAIL = "dinamicas.electronicas@gmail.com"
PROJECT = "RSS2 — Agregador multilingüe de noticias RSS"
MARKER = "Dinámicas Electrónicas"
LICENSE = "MIT"

HEADER = [
    PROJECT,
    f"Copyright (c) 2026 {OWNER} <{EMAIL}>",
    f"SPDX-License-Identifier: {LICENSE}",
]

FOOTER = (
    f"---\n\n© 2026 {OWNER} · <{EMAIL}> · Licencia {LICENSE}\n"
)

# Extensiones que no admiten comentarios o que no son código propio.
SKIP_SUFFIXES = {
    ".json",
    ".csv",
    ".sum",
    ".lock",
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".svg",
    ".ico",
    ".webp",
    ".woff",
    ".woff2",
    ".ttf",
    ".otf",
    ".pdf",
    ".zip",
    ".gz",
    ".wav",
    ".mp3",
    ".pyc",
    ".db",
    ".pt",
    ".bin",
}

SKIP_NAMES = {
    "LICENSE",
    "NOTICE",
    "package-lock.json",
    "go.sum",
}

HASH_SUFFIXES = {
    ".py",
    ".sh",
    ".yml",
    ".yaml",
    ".conf",
    ".env",
    ".toml",
    ".ini",
    ".cfg",
    ".txt",
    ".service",
    ".example",
}

HASH_NAMES = {
    "Makefile",
    ".gitignore",
    ".dockerignore",
    ".env.example",
    ".env.secure.example",
}

SLASH_SUFFIXES = {".go", ".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"}
CSS_SUFFIXES = {".css", ".scss", ".sass", ".less"}
SQL_SUFFIXES = {".sql"}
HTML_SUFFIXES = {".html", ".htm"}
MD_SUFFIXES = {".md", ".markdown"}


def is_dockerfile(name: str) -> bool:
    return name == "Dockerfile" or name.startswith("Dockerfile.")


def style_of(path: Path) -> str | None:
    name = path.name
    suffix = path.suffix.lower()

    if name in SKIP_NAMES or suffix in SKIP_SUFFIXES:
        return None
    if path.parts[0] == "frontend" and name == "package-lock.json":
        return None
    if suffix in MD_SUFFIXES:
        return "markdown"
    if suffix in SQL_SUFFIXES:
        return "sql"
    if suffix in HTML_SUFFIXES:
        return "html"
    if suffix in CSS_SUFFIXES:
        return "block"
    if suffix in SLASH_SUFFIXES:
        return "slash"
    if suffix in HASH_SUFFIXES or name in HASH_NAMES or is_dockerfile(name):
        return "hash"
    return None


def build_header(style: str) -> str:
    if style == "slash":
        return "".join(f"// {line}\n" for line in HEADER)
    if style == "hash":
        return "".join(f"# {line}\n" for line in HEADER)
    if style == "sql":
        return "".join(f"-- {line}\n" for line in HEADER)
    if style == "block":
        body = "".join(f" * {line}\n" for line in HEADER)
        return f"/**\n{body} */\n"
    if style == "html":
        body = "".join(f"  {line}\n" for line in HEADER)
        return f"<!--\n{body}-->\n"
    raise ValueError(style)


def has_header(text: str) -> bool:
    return MARKER in text[:800] or (text.rstrip().endswith(FOOTER.rstrip()))


def apply_header(path: Path, style: str, text: str) -> str:
    if style == "markdown":
        if FOOTER.strip() in text[-400:]:
            return text
        return text.rstrip("\n") + "\n\n" + FOOTER

    header = build_header(style)

    if style == "html":
        newline = text.find("\n")
        if newline == -1:
            return text + "\n" + header
        first = text[:newline].strip().lower()
        if first.startswith("<!doctype"):
            return text[: newline + 1] + header + "\n" + text[newline + 1 :]
        return header + "\n" + text

    # Respeta el shebang (y la línea de codificación de Python si existiera).
    lines = text.splitlines(keepends=True)
    insert_at = 0
    if lines and lines[0].startswith("#!"):
        insert_at = 1
    if (
        len(lines) > insert_at
        and lines[insert_at].startswith("#")
        and "coding" in lines[insert_at][:40]
    ):
        insert_at += 1

    head = "".join(lines[:insert_at])
    rest = "".join(lines[insert_at:])
    if head and not head.endswith("\n"):
        head += "\n"
    return head + header + "\n" + rest


def tracked_files() -> list[Path]:
    out = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        check=True,
        capture_output=True,
    ).stdout
    paths = [Path(p) for p in out.decode("utf-8").split("\0") if p]
    return sorted(p for p in paths if p.is_file())


def main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) > 1 else "check"
    if mode not in {"apply", "check"}:
        print(__doc__)
        return 2

    missing: list[Path] = []
    changed = 0

    for path in tracked_files():
        style = style_of(path)
        if style is None:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue

        if has_header(text):
            continue

        missing.append(path)
        if mode == "apply":
            path.write_text(apply_header(path, style, text), encoding="utf-8")
            changed += 1

    if mode == "apply":
        print(f"Cabeceras aplicadas: {changed}")
        return 0

    if missing:
        print(f"Faltan {len(missing)} cabeceras de autoría:")
        for path in missing:
            print(f"  {path}")
        print("\nEjecuta: make headers")
        return 1

    print("Todas las cabeceras de autoría están presentes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
