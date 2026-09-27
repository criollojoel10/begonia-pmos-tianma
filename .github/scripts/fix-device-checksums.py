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

La lista de ficheros que se hashea no esta escrita en el codigo: se deduce del
source= del propio APKBUILD. La primera version si la tenia hardcodeada, y al
anadir mediatek-wifi.{sh,service} al source= se te olvidó updatingarla. El bloque
sha512sums se reescribia con los tres ficheros de antes y los dos nuevos
quedaban fuera, de modo que abuild abortaba con

    >>> ERROR: device-xiaomi-begonia: mediatek-wifi.sh is missing in checksums

Sin paquete no hay rootfs, ni initramfs, ni imagen, y los pasos siguientes
fallan todos en cascada, culpando a cosas que no son el problema: asi fue
el run 36330479935, donde tambien se quejo de un initramfs con magic
desconocido que en realidad no existia.

Este script reescribe solo la COPIA del APKBUILD que hay en el arbol de
pmaports del runner, nunca el fichero del overlay del repo, asi que el
`git diff` del checkout de pmaports sigue mostrando el cambio real.

Uso: fix-device-checksums.py <pmaports_dir>
"""

import hashlib
import pathlib
import re
import sys

MARK = 'sha512sums="'


def parse_source(apk: pathlib.Path) -> list[str]:
    """Los nombres de source=.

    El valor suele ir entre comillas y puede ocupar varias lineas, asi que se
    lee contando comillas. Cortar por "la siguiente linea con =" no vale: entre
    source= y sha512sums se cuelan build() y package(), y sus parametros se
    colarian como si fueran ficheros de source.
    """
    text = apk.read_text()
    m = re.search(r"^source=", text, re.M)
    if not m:
        print("ERROR: el APKBUILD no tiene source=", file=sys.stderr)
        raise SystemExit(1)
    rest = text[m.end():]
    rest = rest.lstrip()
    if rest[:1] in ('"', "'"):
        q = rest[0]
        end = rest.find(q, 1)
        if end < 0:
            print("ERROR: source= con comilla sin cerrar", file=sys.stderr)
            raise SystemExit(1)
        raw = rest[1:end]
    else:
        raw = rest.splitlines()[0]
    # Los tokens con $ no son nombres de fichero: son pmaports los que los
    # expande al construir. No se pueden hashear aqui, asi que se descartan.
    names = []
    for tok in raw.split():
        if "$" in tok or ";" in tok:
            continue
        names.append(tok)
    return names


def parse_current_sums(apk: pathlib.Path) -> dict[str, str]:
    """hash por nombre del bloque sha512sums que hay ahora mismo."""
    sums: dict[str, str] = {}
    inside = False
    for ln in apk.read_text().splitlines():
        if ln.startswith(MARK):
            inside = True
            continue
        if inside:
            if ln.strip() == '"':
                break
            parts = ln.split()
            if len(parts) == 2 and len(parts[0]) == 128:
                sums[parts[1]] = parts[0]
    return sums


def main() -> int:
    if len(sys.argv) != 2:
        print(f"uso: {sys.argv[0]} <pmaports_dir>", file=sys.stderr)
        return 2
    d = pathlib.Path(sys.argv[1]) / "device/testing/device-xiaomi-begonia"
    apk = d / "APKBUILD"
    if not apk.is_file():
        print(f"ERROR: no existe {apk}", file=sys.stderr)
        return 1

    # Todo lo que este en source= y exista en el arbol se recalcula. Lo que no
    # exista (una descarga) conserva el hash que ya tenia, porque recalcularlo
    # aqui no es posible y borrarlo seria peor. La lista NO esta hardcodeada a
    # proposito: la primera version la tenia, y al anadir
    # mediatek-wifi.{sh,service} al source= se te olvidó updatingarla, con lo que
    # el bloque se reescribia sin ellos y abuild abortaba con
    #   >>> ERROR: device-xiaomi-begonia: mediatek-wifi.sh is missing in checksums
    # Sin paquete no hay rootfs, ni initramfs, ni imagen, y todos los pasos
    # siguientes fallan en cascada (asi fue el run 36330479935).
    prev = parse_current_sums(apk)
    local, remote = [], []
    for name in parse_source(apk):
        if (d / name).is_file():
            local.append(name)
        else:
            remote.append(name)
            if name not in prev:
                print(f"ERROR: {name} esta en source=, no es fichero local y no "
                      f"tiene hash en sha512sums", file=sys.stderr)
                return 1
    if not local:
        print("ERROR: source= no aporta ningun fichero local", file=sys.stderr)
        return 1

    shas = {f: hashlib.sha512((d / f).read_bytes()).hexdigest() for f in local}
    for f in local:
        if f in prev and prev[f] != shas[f]:
            print(f"  (cambia) {f}")

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
            for f in remote:
                out.append(f"{prev[f]}  {f}\n")
            for f in local:
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
    for f in remote:
        print(f"  {prev[f]}  {f}  (descarga, hash conservado)")
    for f in local:
        print(f"  {shas[f]}  {f}")
    print("sha512sums del APKBUILD de device-xiaomi-begonia reescrito "
          f"({len(local)} local, {len(remote)} descarga)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
