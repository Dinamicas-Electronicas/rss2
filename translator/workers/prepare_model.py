# RSS2 — Agregador multilingüe de noticias RSS
# Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
# SPDX-License-Identifier: MIT

"""Prepara el modelo NLLB en formato CTranslate2 antes de arrancar.

Uso (servicio de un solo uso del compose):

    python -m workers.prepare_model

El modelo no se versiona ni va dentro de la imagen: la primera vez se
descarga de HuggingFace y se convierte con `ct2-transformers-converter`
(~2,4 GB, varios minutos). Si ya existe `model.bin` termina al instante.

El bloqueo con flock evita que dos replicas conviertan el mismo directorio a
la vez cuando el servicio de preparacion no esta en juego.
"""

from __future__ import annotations

import fcntl
import os
import subprocess
import sys
from pathlib import Path

MODEL_DIR = Path(os.environ.get("CT2_MODEL_PATH", "/models/nllb-ct2"))
MODEL_NAME = os.environ.get("UNIVERSAL_MODEL", "facebook/nllb-200-distilled-600M")
QUANTIZATION = (os.environ.get("CT2_COMPUTE_TYPE") or "int8").strip() or "int8"
LOCK_FILE = MODEL_DIR.parent / ".model-prepare.lock"


def model_ready() -> bool:
    """El conversor escribe model.bin al final: su presencia = modelo completo."""
    return (MODEL_DIR / "model.bin").is_file()


def main() -> int:
    MODEL_DIR.parent.mkdir(parents=True, exist_ok=True)

    with open(LOCK_FILE, "w", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)

        if model_ready():
            print(f"[models] modelo listo en {MODEL_DIR}", flush=True)
            return 0

        MODEL_DIR.mkdir(parents=True, exist_ok=True)
        print(
            f"[models] convirtiendo {MODEL_NAME} -> {MODEL_DIR} "
            f"(quantization={QUANTIZATION}); puede tardar varios minutos",
            flush=True,
        )
        command = [
            "ct2-transformers-converter",
            "--model",
            MODEL_NAME,
            "--output_dir",
            str(MODEL_DIR),
            "--quantization",
            QUANTIZATION,
            "--force",
        ]
        try:
            subprocess.run(command, check=True)
        except FileNotFoundError:
            print(
                "[models] no se encontro ct2-transformers-converter en el PATH",
                file=sys.stderr,
                flush=True,
            )
            return 1
        except subprocess.CalledProcessError as exc:
            print(
                f"[models] la conversion fallo (codigo {exc.returncode})",
                file=sys.stderr,
                flush=True,
            )
            return 1

        if not model_ready():
            print(
                "[models] la conversion termino sin generar model.bin",
                file=sys.stderr,
                flush=True,
            )
            return 1

        print(f"[models] modelo listo en {MODEL_DIR}", flush=True)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
