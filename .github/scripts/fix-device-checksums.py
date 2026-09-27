#!/usr/bin/env python3
"""Reescribe el bloque sha512sums del APKBUILD de device-xiaomi-begonia.

Por que existe: los tres ficheros de `source=` (deviceinfo,
kernel-cmdline.conf, modules-initfs) son *del propio arbol*, no descargas, y
este repo sobreescribe el APKBUILD de pmaports. El sha512sums que trae
upstream es el de los ficheros de pmaports, asi que en cuanto se toca
deviceinfo (por ejemplo para poner deviceinfo_rootfs_image_sector_size=4096)
el hash deja de cuadrar y abuild aborta con:

    deviceinfo: FAILED
    sha512sum: WARNING: 1 of 1 computed checksums did NOT match
    >>> ERROR: device-xiaomi-begonia: Use 'abuild checksum' to generate/update the checksum(s)

Eso solo aparece cuando el paquete se construye de verdad. Con pkgrel=0 apk
daba por buena la version publicada en edge y el paquete nunca se compilaba,
asi que el hash roto llevaba semanas sin que nada lo delatara. El fix de
pkgrel=1 (commit 6e4fa58, para que la imagen lleve
firmware-xiaomi-begonia-connectivity) destapo el problema en el run
36307235048.

Este script reescribe solo la COPIA del APKBUILD que hay en el arbol de
pmaports del runner, nunca el fichero del overlay del repo, asi que el
`git diff` del checkout de pmaports sigue mostrando el cambio real.

Uso: fix-device-checksums.py <pmaports_dir>
"""

import hashlib
import pathlib
import sys

FILES = ["deviceinfo", "kernel-cmdline.conf", "modules-initfs"]
MARK = 'sha512sums="'


def main() -> int:
    if len(sys.argv) != 2:
        print(f"uso: {sys.argv[0]} <pmaports_dir>", file=sys.stderr)
        return 2
    d = pathlib.Path(sys.argv[1]) / "device/testing/device-xiaomi-begonia"
    apk = d / "APKBUILD"
    if not apk.is_file():
        print(f"ERROR: no existe {apk}", file=sys.stderr)
        return 1

    shas = {}
    for f in FILES:
        p = d / f
        if not p.is_file():
            print(f"ERROR: falta el fichero local {p}", file=sys.stderr)
            return 1
        shas[f] = hashlib.sha512(p.read_bytes()).hexdigest()

    lines = apk.read_text().splitlines(keepends=True)
    out, i, changed = [], 0, False
    while i < len(lines):
        if lines[i].startswith(MARK):
            while i < len(lines) and lines[i].strip() != '"':
                i += 1
            if i >= len(lines):
                print("ERROR: sha512sums sin cerrar en el APKBUILD", file=sys.stderr)
                return 1
            i += 1  # salta la linea de cierre
            out.append(MARK + "\n")
            for f in FILES:
                out.append(f"{shas[f]}  {f}\n")
            out.append('"\n')
            changed = True
            continue
        out.append(lines[i])
        i += 1

    if not changed:
        print("ERROR: no hay bloque sha512sums en el APKBUILD", file=sys.stderr)
        return 1

    apk.write_text("".join(out))
    for f in FILES:
        print(f"  {shas[f]}  {f}")
    print("sha512sums del APKBUILD de device-xiaomi-begonia reescrito")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
