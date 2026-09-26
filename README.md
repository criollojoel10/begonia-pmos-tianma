# begonia-pmos-tianma

Compila postmarketOS **edge con kernel 7.1 + variante Tianma** para el Xiaomi Redmi Note 8 Pro (`xiaomi-begonia`), en GitHub Actions, con drivers USB-OTG/dongle (Ethernet + WiFi + serial). Incluye **KDE Plasma Mobile**.

El build corre en el runner (no se necesita hardware local potente) y produce artefactos listos para flashear por fastboot.

## El problema que resuelve

El kernel mainline 6.16.4 que trae pmOS **solo soporta la variante de panel CSOT**. Los Redmi Note 8 Pro con panel **Tianma** (como el de este proyecto) quedan con el **touch invertido**.

- `mt6785-xiaomi-begonia.dts` (6.16) tiene `compatible = "xiaomi,begonia-csot-nt36672a"` y `firmware-name = "novatek/nt36672a_begonia_csot.bin"`.
- La rama **7.1** del kernel separa las dos variantes: `mt6785-xiaomi-begonia-csot.dts` y `mt6785-xiaomi-begonia-tianma.dts`.

La solución es el **MR !8852** de Dinolek ("Update mt6785 kernel to 7.1, add support for Tianma variant"), que:

1. Actualiza el kernel a **7.1** (build con **clang/LLVM**, BTF, Shadow Call Stack).
2. Parte el device en **subpackages de kernel**: `device-xiaomi-begonia-kernel-csot` y `device-xiaomi-begonia-kernel-tianma`.
3. Añade el firmware de touch **Tianma** (`nt36672a_begonia_tianma.bin`).
4. Actualiza `modules-initfs` (mediatek-drm, panel-novatek-nt36672a, etc.).

Este repo aplica ese MR como parche y selecciona la variante `tianma` vía `kernel = tianma` en la config de pmbootstrap.

## Método rápido confirmado: swap de firmware tianma en el kernel 6.16.4 (sin rebuild)

**No hace falta kernel 7.1 ni MR !8852 para el touch en 6.16.4.** El touch Tianma funciona copiando el firmware tianma con el **nombre que el DTB espera** (`nt36672a_begonia_csot.bin`), porque el driver `novatek-nvt-ts-core` lee `firmware-name` del device-tree y hace `request_firmware` con ese nombre exacto. El DTB 6.16.4 solo referencia la variante csot, así que el binario tianma debe usar ese nombre.

Pasos (en el device, vía SSH):

```
# 1) Confirmar que el firmware es tianma (no csot):
md5sum /lib/firmware/novatek/nt36672a_begonia_tianma.bin.zst
#    tianma: 7d67c2e9167f1a630576c177c1b831f7  (53321 B)
#    csot:   52f5e96f84fbdd6cbed2e98790a202df  (53731 B)

# 2) Copiar tianma bajo el nombre que espera el DTB, en ambas rutas:
sudo cp /lib/firmware/novatek/nt36672a_begonia_tianma.bin.zst \
        /lib/firmware/novatek/nt36672a_begonia_csot.bin.zst
sudo cp /lib/firmware/novatek/nt36672a_begonia_csot.bin.zst \
        /usr/lib/firmware/novatek/nt36672a_begonia_csot.bin.zst

# 3) Verificar que ahora el "csot" es el tianma:
md5sum /lib/firmware/novatek/nt36672a_begonia_csot.bin.zst  # = 7d67c2e9...

# 4) Reiniciar.
sudo reboot
```

Verificación tras el reinicio:

```
lsmod | grep novatek          # novatek_nvt_ts_spi + novatek_nvt_ts_core cargados
dmesg | grep -i novatek       # sin errores de request_firmware
cat /proc/bus/input/devices   # el touch (input2, spi@11019000) con ejes correctos
```

Resultado confirmado: táctil Tianma con ejes correctos en pmOS 6.16.4, sin compilar nada.

## Cómo funciona el workflow

`.github/workflows/build-tianma.yaml` (basado en el workflow `combined` de `begonia-postmarketos-build`):

1. **Free disk** + dependencias del host (qemu-user-static, parted, etc.).
2. Clona `pmbootstrap` (depth 1).
3. Clona `pmaports` (parcial `--filter=blob:none`) y hace `checkout` del base del MR (`e2572a0d`) + `git am --3way` del parche `.github/patches/mr8852.patch`.
4. Escribe la config de pmbootstrap con **`kernel = tianma`** y `ui = phosh` (base) + `cross = true`.
5. Restaura cachés (apk + distfiles + ccache).
6. Parchea pmbootstrap para CI (`patch_pmbootstrap.py`).
7. Añade drivers dongle (`enable_kernel_drivers.sh`) y fuerza rebuild del kernel.
8. Instala el rootfs (Phosh) y luego añade **Plasma Mobile**.
9. Exporta/salva/subida de artefactos (`boot.img`, `initramfs`, `vmlinuz`, `xiaomi-begonia.img`).

### Drivers dongle añadidos

`enable_kernel_drivers.sh` añade a la config del kernel:

- **Ethernet USB**: `AX8817X`, `AX88179`, `RTL8150`, `RTL8152`, `CDC_EEM`, `CDC_NCM`, `CDCETHER`, `DM9601`, `SMSC95XX`, `SR9700`, `SR9800`.
- **WiFi**: `RTL8XXXU` (Realtek, p. ej. TP-Link W821N), `MT76`/`MT76_USB`/`MT76X0U`/`MT76X2U`/`MT7921U` (MediaTek).
- **Serial USB**: `PL2303`, `FTDI_SIO`, `CP210X`.

(El `.config` 7.1 del MR ya trae la mayoría; el script añade los que faltan.)

## Caché / buenas prácticas

- **apk + distfiles** (`cache_apk_*`, `cache_distfiles`): evita re-descargar paquetes Alpine y el tarball del kernel (~200 MB) entre runs.
- **ccache** (`cache_ccache_*`): acelera recompilaciones del kernel.
- El `rm -rf $PMB_WORK` de la config ocurre **antes** de restaurar caché, así la caché no se borra.
- Las cachés se guardan al final del job automáticamente (`actions/cache@v4` con clave estática incremental).

## Uso

1. Repo → **Actions** → **Build pmOS begonia (Tianma, kernel 7.1) + Plasma Mobile** → **Run workflow**.
   - `fde`: `false` (sin cifrado).
   - `extra_space`: `4096`.
   - `cross`: `true` (compilación cruzada, recomendado; `false` = build nativo emulado con qemu, mucho más lento).
2. Al terminar, descargar el artefacto `pmos-begonia-tianma-7.1-cross-true`.

## Build WiFi/Bluetooth (kernel 6.16.4 begonia-conn-wifi)

Para el WiFi/BT integrado del SoC y los dongles USB se usa **`build-wifi.yaml`**, que construye
el kernel de la rama `begonia-conn-wifi` del fork `mirror/linux` (`3a1ea769`, v6.16.4) en lugar
del 7.1/MR !8852:

- Aplica overlays en `pmaports` (sin parches `git am`, para no depender de commits móviles):
  - `linux-postmarketos-mediatek-mt6785/APKBUILD` → kernel `minorum/linux` @ `3a1ea769` (build gcc).
  - `firmware-xiaomi-begonia/APKBUILD` → commit `33aa9fe1` con subpaquete nuevo
    `firmware-xiaomi-begonia-connectivity` (7 blobs MTK en `/lib/firmware/mediatek/`).
  - `device-xiaomi-begonia/` → depende de `firmware-xiaomi-begonia-connectivity` y lleva
    `deviceinfo_flash_fastboot_partition_vbmeta="vbmeta"`.
- `.github/scripts/enable_kernel_drivers.sh` activa en el config del kernel:
  - Ethernet USB: `USB_NET_AX8817X/AX88179_178A/RTL8150/RTL8152/CDCETHER/CDC_NCM/DM9601/SMSC95XX/SR9700/SR9800`.
  - WiFi USB Realtek: `RTL8XXXU` (TP-Link TL-WN821N) y MediaTek: `MT76`/`MT76_USB`/`MT7921U`.
  - Bluetooth USB: `BT_LE=y`, `BT_HCIBTUSB` (RTL8821C, CSR).
  - Stack MTK integrado: **opt-in** vía el input `mtk_gen4m` del workflow (env `MTK_GEN4M`, por
    defecto `0` = desactivado). Ver abajo por qué.
- Artefacto resultante: `pmos-begonia-wifi-6.16.4-cross-true`.

### `mtk_gen4m`: por qué está desactivado por defecto

`wlan_gen4m.ko` (el stack wifi propietario de MediaTek) llama a `wireless_send_event()`, que solo
se compila con `CONFIG_WEXT_CORE`. Sin esa opción, modpost aborta el kernel entero:

```
ERROR: modpost: "wireless_send_event" [.../wireless_core.ko] undefined!
```

Es un fallo de build, no de runtime: no hay forma de degradar gracefully, el kernel no compila. Por eso
el input existe en vez de estar siempre activo:

| `mtk_gen4m` | Qué pasa |
|---|---|
| `false` (por defecto) | Stack MTK fuera. El kernel compila. Los dongles USB (`rtl8xxxu`, `mt76`) no lo necesitan. |
| `true` | Añade `MTK_WMT_FWPORT`, `MTK_WMT_DRV`, `MTK_WLAN_GEN4M`, `MTK_WMT_FWPORT_BTIF` **y `CONFIG_WEXT_CORE=y`**, que es lo que resuelve el símbolo. |

Ambos caminos se compilaron y llegaron hasta `modules_install` sin errores de modpost, así que el
stack es viable; lo que no está verificado es que el wifi interno funcione en el dispositivo, porque
falta probarlo en hardware. Por eso el run por defecto es el de los dongles: es el que desbloquea
usar el hub ahora mismo.

Ejecutar igual que el workflow Tianma (Actions → **Build pmOS begonia (WiFi/Bluetooth, kernel 6.16.4...)**). El flasheo y la verificación son los mismos (sección de abajo); `uname -r` dará `6.16.4-postmarketos-mediatek-mt6785`.

## Flasheo (fastboot)

```
fastboot flash userdata xiaomi-begonia.img   # rootfs (pmOS_boot + pmOS_root)
fastboot flash boot boot.img
fastboot flash vbmeta vbmeta.img             # AVB flags=2 (verificación desactivada)
fastboot reboot
```

El `vbmeta.img` se genera con `avbtool make_vbmeta_image --flags 2 --padding_size 2048 --output vbmeta.img` (flags=0 → bootloop a fastboot).

## Verificación

USB networking (RNDIS): dispositivo `172.16.42.1`, host `172.16.42.2/24`.

```
ssh joel@172.16.42.1
uname -r          # 7.1.x-postmarketos-mediatek-mt6785
```

Touch Tianma: en `/proc/device-tree` o `dmesg` debe aparecer el panel `xiaomi,begonia-tianma-nt36672a`.

## Estado del WiFi (verificado en el dispositivo, kernel 6.16.4)

El SoC WiFi/BT de begonia usa el stack propietario de MediaTek (`wmt`/`connsys`/`btif`),
que NO está en el kernel 6.16.4 mainline. Verificado en el dispositivo real:

- Sin nodo WiFi/BT en el device-tree (`/proc/device-tree` sin `wifi`/`wlan`/`consys`).
- Sin drivers de radio compilados (ni `mt76` ni `wmt`/`connsys` ni `btmtk`). Solo existen
  `cfg80211.ko` y `mac80211.ko` (infraestructura, sin radio detrás).
- Sin firmware en `/lib/firmware/mediatek/`.
- Único rfkill presente: `nfc0` (NFC, no WiFi/BT).

Conclusión: **no se puede activar WiFi en este kernel**. Para el WiFi hace falta un rebuild
con la rama `begonia-conn-wifi` del fork `mt6785-mainline/linux` (forward-port del stack
vendor a 6.16: `drivers/misc/mediatek/btif`, `srh_patch`, DTS con nodo WiFi) más el blob de
conectividad del fork `mt6785-mainline/firmware`. El driver wireless USB (`mt76`, `rtl8xxxu`)
también se puede compilar como alternativa/dongle, pero no se cargó ninguno en 6.16.4.

## Errores que no hay que repetir

- **`zstd` ausente en makedepends rompe el kernel.** El config de pmaports trae
  `CONFIG_MODULE_COMPRESS_ZSTD=y` + `MODULE_COMPRESS_ALL=y`, así que `modules_install` invoca el
  binario `zstd` y sin él falla con
  `make[2]: *** [scripts/Makefile.modinst:162: .../sha512-ce.ko.zst] Error 127` /
  `/bin/sh: line 0: zstd: not found`. Lo arregló upstream en el **MR !9035** (`bb84c79b7`, "build with
  LLVM"), que además movió `INSTALL_MOD_PATH` a `"$pkgdir"/usr`. Nuestro overlay estaba basado en la
  versión **pre-!9035**; ya está rebasado. El error es engañoso porque el config de una copia local
  vieja de pmaports lo tenía desactivado y no lo reproducía: **el config que se usa es el del
  checkout de pmaports, no el de tu copia local**.
- **`INSTALL_MOD_PATH="$pkgdir"` deja los módulos en `/lib/modules`**; Alpine con `/usr` merge (y el
  dispositivo vivo) los espera en `/usr/lib/modules`. Como upstream.
- **Pinear pmaports por SHA rompe pmbootstrap.** `pmb/helpers/git.py` lee literalmente
  `git show origin/main:channels.cfg`; un fetch por SHA deja HEAD detached y sin `origin/main`, y
  aborta con `Failed to read channels.cfg from 'origin/main' branch`. Si se pina, hay que crear la
  ref a mano con `git update-ref refs/remotes/origin/main FETCH_HEAD`.
- **El config del kernel es un source sin URL**: pmbootstrap lo copia del checkout de pmaports, así
  que el `sha512sums` del APKBUILD documenta pero no verifica, y `pmbootstrap checksum` lo
  reescribe con el valor del config ya mutado por `enable_kernel_drivers.sh`. Por eso está pineado
  el commit de pmaports: si upstream mueve el config, nadie se entera.
- **`postmarketos-ui-plasma-mobile` es soft-fail a propósito.** El step que lo compila usa
  `set -e`, así que si el build de la UI falla se perdía el `install` posterior y con él la imagen
  entera. Ahora si no compila cae a una imagen Phosh funcional y avisa con `::warning::`.
- **No swapear solo el kernel** (6.16 → 7.1) sin regenerar el initramfs: los `.ko` del initramfs llevan `vermagic` de 6.16 y el kernel 7.1 no los carga → sin display/touch. Por eso se hace build completo con pmbootstrap.
- **`flags=0` en vbmeta** → LK rechaza el boot (bootloop a fastboot). Usar `flags=2`.
- **`kernel = tianma`** es obligatorio; con el default (`stable`) falla porque el device ya no depende directo del kernel (solo expone las subpackages `-kernel-csot`/`-kernel-tianma`).
- **No correr el flasheo con el teléfono en otra variante**: verificar qué panel tiene antes (CSOT vs Tianma).

## Referencias

- MR !8852: https://gitlab.postmarketos.org/postmarketOS/pmaports/-/merge_requests/8852
- Kernel mainline mt6785: https://github.com/external-mirrors/mt6785-mainline-linux (ramas `6.16`, `7.1`, `battery-downstream`)
- Firmware touch: https://gitlab.postmarketos.org/mt6785-mainline/firmware
- Wiki pmOS begonia: https://wiki.postmarketos.org/wiki/Xiaomi_Redmi_Note_8_Pro_(xiaomi-begonia)
