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

## Errores que no hay que repetir

- **No swapear solo el kernel** (6.16 → 7.1) sin regenerar el initramfs: los `.ko` del initramfs llevan `vermagic` de 6.16 y el kernel 7.1 no los carga → sin display/touch. Por eso se hace build completo con pmbootstrap.
- **`flags=0` en vbmeta** → LK rechaza el boot (bootloop a fastboot). Usar `flags=2`.
- **`kernel = tianma`** es obligatorio; con el default (`stable`) falla porque el device ya no depende directo del kernel (solo expone las subpackages `-kernel-csot`/`-kernel-tianma`).
- **No correr el flasheo con el teléfono en otra variante**: verificar qué panel tiene antes (CSOT vs Tianma).

## Referencias

- MR !8852: https://gitlab.postmarketos.org/postmarketOS/pmaports/-/merge_requests/8852
- Kernel mainline mt6785: https://github.com/external-mirrors/mt6785-mainline-linux (ramas `6.16`, `7.1`, `battery-downstream`)
- Firmware touch: https://gitlab.postmarketos.org/mt6785-mainline/firmware
- Wiki pmOS begonia: https://wiki.postmarketos.org/wiki/Xiaomi_Redmi_Note_8_Pro_(xiaomi-begonia)
