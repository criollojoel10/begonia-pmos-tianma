# begonia-pmos-tianma

Compila postmarketOS **edge con el kernel mainline 6.16.4** para el Xiaomi Redmi Note 8 Pro (`xiaomi-begonia`) en GitHub Actions, con el **stack de conectividad interno de MediaTek** (wifi `wlan_gen4m`) y los drivers USB-OTG/dongle (Ethernet + WiFi + serial). Incluye **KDE Plasma Mobile**.

El build corre en el runner (no se necesita hardware local potente) y produce artefactos listos para flashear por fastboot.

## Estado: build verde

El run **`36309275971`** (commit `03630c8`) salió **verde** el 27-09-2026: kernel
con los drivers, initramfs con el firmware Tianma, los 7 blobs MediaTek en la
rootfs, Plasma Mobile y export. Artifact `pmos-begonia-wifi-6.16.4-cross-false`
(id `10928553872`). Instrucciones de flasheo en `kupfer-img/LEEME-flash.md`.

### Los dos runs anteriores y por qué ya no valen

| Run | Commit | Qué pasó |
|---|---|---|
| `36304158010` | `bfc2bdb` | Verde, pero **su imagen no vale para probar el wifi interno**: al montar la rootfs se vio que **no tenía ni un blob en `/lib/firmware/mediatek/`**. El subpaquete `firmware-xiaomi-begonia-connectivity` (7 blobs, 766 KB) sí se construía, pero no se instalaba, porque el `APKBUILD` sobrepuesto de `device-xiaomi-begonia` tenía exactamente la versión publicada en `edge` (`6-r0`) y apk da por buena la del repo en vez de construir la local. |
| `36307235048` | `6e4fa58` | El `pkgrel=1` arregló lo anterior y destapó un **hash roto que llevaba semanas sin comprobarse**: el `sha512sums` del APKBUILD de pmaports es el de sus propios ficheros, y nuestro `deviceinfo` está modificado (`deviceinfo_rootfs_image_sector_size="4096"` + `deviceinfo_flash_sparse`), así que `abuild` abortó con `Use 'abuild checksum'`. |
| **`36309275971`** | **`03630c8`** | **Verde. Esta es la imagen buena.** Además del `pkgrel=1`, lleva el sha512 real de los tres ficheros locales y un paso de CI que lo recalcula en cada build. |


## El problema que resuelve

El kernel mainline que trae pmOS **solo soporta la variante de panel CSOT**, y pmOS instala **solo el firmware CSOT** del táctil. Los Redmi Note 8 Pro con panel **Tianma** (como el de este proyecto) quedan con el **touch invertido**: la pantalla enciende y no hay ningún error en el log, pero los ejes van cruzados.

- `mt6785-xiaomi-begonia.dts` (6.16) tiene `compatible = "xiaomi,begonia-csot-nt36672a"` y `firmware-name = "novatek/nt36672a_begonia_csot.bin"`.
- La rama **7.1** del kernel (MR !8852 de Dinolek) separa las dos variantes en dos DTS y en dos subpackages de kernel, pero **no está mergeada** en el commit de pmaports que usa este repo, así que aquí se compila el 6.16.4.

**Este repo lo resuelve en la imagen**: el paquete `firmware-xiaomi-begonia-touchscreen` instala los dos binarios y copia el **Tianma encima del nombre CSOT**, que es el que el driver pide. El initramfs se construye ya con el binario correcto, así que el táctil va bien en el primer arranque sin tocar nada el móvil. El CI lo comprueba comparando el md5 del fichero (un `ls` no lo detecta: los dos nombres existen siempre).

## Si aun así el touch sale invertido (sw manual)

**No hace falta kernel 7.1 ni MR !8852 para el touch en 6.16.4.** El touch Tianma funciona copiando el firmware tianma con el **nombre que el DTB espera** (`nt36672a_begonia_csot.bin`), porque el driver `novatek-nvt-ts-spi` lee `firmware-name` del device-tree y hace `request_firmware` con ese nombre exacto. El DTB 6.16.4 solo referencia la variante csot, así que el binario tianma debe usar ese nombre. Es lo que hace el paquete de firmware de este repo al construir la imagen; esto es el equivalente manual por si hubiera que rehacerlo en un móvil ya instalado.

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

### Dos trampas al añadir drivers, y cómo se pagan

El run `36262126701` construyó los tres módulos del stack MTK correctamente y falló después, en el
step de verify, por cinco dongles. Las dos causas fueron de nombres, no de código:

1. **Kconfig es *case-sensitive* y `olddefconfig` descarta en silencio lo que no reconoce.** No hay
   ningún aviso: el símbolo simplemente no existe en el `.config`. `CONFIG_MT76` no existe (es
   `MT76_CORE`, y `MT76_USB` depende de él, así que se caía en cascada), `MT76X0U`/`MT76X2U` llevan la
   `x` minúscula (`MT76x0U`, `MT76x2U`) y `USB_SIERRA_NET` faltaba. Peor: `USB_RTL8150` **sí** existe
   como símbolo Kconfig, pero no compila ningún driver (el Makefile produce `rtl8150.ko` y no hay
   `r8150.c`), así que un símbolo "válido" no garantiza un módulo.
2. **El nombre del módulo no tiene por qué parecerse al del símbolo.** De las líneas `LD [M]` del log
   salen los nombres reales: el driver `USB_RTL8150` produce **`rtl8150.ko`**, y el transporte común de
   mt76 es **`mt76-usb.ko`** (con guion). Los `rtw88_*` llevan su variante dentro: `rtw88_8812au.ko`,
   `rtw88_8821au.ko`, `rtw88_8822bu.ko`.

Por eso el verify lista los `.ko` por su nombre real y no por el símbolo del Kconfig.

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
  - WiFi USB Realtek: `RTL8XXXU` (TP-Link TL-WN821N) y MediaTek: `MT76_CORE`/`MT76_USB`/`MT76x0U`/`MT76x2U`/`MT7921U`, más los `RTW88_*` de los dongles AC de 20-30 € (`RTW88_CORE`, `RTW88_USB`, `RTW88_8812AU`, `RTW88_8821AU`, `RTW88_8822BU`).
  - Ethernet USB: también `USB_SIERRA_NET`.
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
| `true` | Añade `MTK_WMT_FWPORT`, `MTK_WMT_DRV`, `MTK_WLAN_GEN4M`, `MTK_WMT_FWPORT_BTIF` **y `CONFIG_CFG80211_WEXT=y`**. |

Sobre el símbolo: hay que activar **`CFG80211_WEXT`**, no `WEXT_CORE`. En `net/wireless/Kconfig`,
`WEXT_CORE` es `def_bool y` + `depends on CFG80211_WEXT || WIRELESS_EXT`, o sea un símbolo **oculto**
sin prompt: poner `CONFIG_WEXT_CORE=y` a mano no sirve, `make olddefconfig` lo recalcula a `n` y borra
la línea del `.config`, y entonces `modpost` aborta el kernel entero con
`ERROR: modpost: "wireless_send_event" [.../wlan_gen4m.ko] undefined!` (es el fallo del run
`36260038275`). `CFG80211_WEXT` sí es un bool con prompt y hace `select WEXT_CORE` (y con él
`WEXT_PROC`), que es justo lo que compila `net/wireless/wext-core.o` → `wireless_core.ko`.

Con `mtk_gen4m=false` el kernel compila y quedan los drivers de dongle. Con `true`, el kernel llega
hasta `modules_install` **verificado**: el run `36262126701` confirmó los tres módulos del stack
(`wmt_drv.ko`, `wlan_gen4m.ko`, `mtk-vendor-btif.ko`); el run falló después, solo en el verify, por
nombres de módulo mal escritos en la lista de dongles (fix `d664db9`, ver más abajo).

Lo que **no** está verificado es el **empaquetado**, no el driver: que los módulos carguen en orden,
que el firmware esté donde el driver lo busca y que el `1` del trigger se comporte como en el
bring-up de su autor. El driver en sí **sí funciona en un begonia**, y lo verificó quien lo escribió
([ver](#el-wifi-verificado-por-su-autor-sin-probar-por-nosotros)).

### El DTS del fork sí está completo

La parte de device tree ya no es un obstáculo: `mt6785.dtsi` del fork trae `wifi@18000000`
(`compatible = "mediatek,wifi"`), `consys@18002000` (`mediatek,mt6785-consys`, con los 12 `reg` en el
orden que espera `consys_read_reg_from_dts`) y `btif@1100c000` (`mediatek,btif`), más
`mt6785-xiaomi-begonia.dts` con `consys_reserved` (4 MB no-map) y `wifi_mem` (3 MB
`shared-dma-pool`). `mtk_wcn_consys_hw.c` sí tiene `mediatek,mt6785-consys` en su tabla de compatibles.
Lo que sí queda como *placeholder* es el `WIFI_EINT` (`GIC_SPI 78`, el IRQ de wake del wifi que el
bootloader de fábrica sourcea), y los pines `gpio_combo_*` están omitidos. El `wmac@18000000` de
routers está `status = "disabled"` a propósito, para no chocar con el stack de fabricante.

El driver **no se autoprobea**: los `platform_device` existen desde `of_platform_populate`, pero hay que
cargar los módulos en orden y usar el trigger:

```sh
# .github/scripts/mtk-wifi-test.sh hace todo esto y da un veredicto.
# Su paso 8 vuelca además /proc/driver/{wmt_dbg,wmt_dump_info,wmt_aee}, la
# instrumentación que dejó el propio autor del fwport: si wlan0 no sale, ahí
# está el motivo (BTIF / conn-MCU / firmware).
modprobe mtk-vendor-btif        # transporte de control hacia el conn-MCU
modprobe wmt_drv                # crea /dev/wmtWifi
modprobe wlan_gen4m             # registra el probe de gen4m
printf 1 > /dev/wmtWifi         # wmt_dev_set_hif_btif() + mtk_wcn_wmt_func_on(WIFI)
```

### Firmware que pide (ya está en la imagen)

`firmware-xiaomi-begonia-connectivity` los instala en `/lib/firmware/mediatek/`, y el kernel tiene
`CONFIG_FW_LOADER_COMPRESS_ZSTD=y` así que los `.zst` los descomprime él:

| Fichero | Lo pide |
|---|---|
| `WMT_SOC.cfg` | `wmt_conf.h` (con fallback `WMT.cfg`) |
| `WMT_STEP.cfg` | `wmt_step.h` (opcional) |
| `soc1_0_patch_mcu_2a_1_hdr.bin` | `wmt_dev.c:459` |
| `soc1_0_ram_mcu_2a_1_hdr.bin`, `soc1_0_ram_wifi_2a_1_hdr.bin`, `soc1_0_ram_bt_2a_1_hdr.bin` | `wmt_ctrl.c:654-656` |
| `WIFI_RAM_CODE_soc1_0_2a_1.bin` | `gl_kal.c` → `connacConstructFirmwarePrio()`; el `2a` sale de `CFG_WIFI_IP_SET(2)` + `kalGetFwFlavor()` en `plat/mt6785/plat_priv.c:122`, que devuelve `'a'` |
| `wifi.cfg` | `gl_init.c:3361`, `wlanGetConfig()`, llamada desde `wlanOnPreAdapterStart()` con `CFG_SUPPORT_CFG_FILE=1`. **No hace falta para arrancar**: primero hace `wlanCfgInit(prAdapter, NULL, 0, 0)`, o sea que parte de la tabla compilada, y solo vuelve a llamar `wlanCfgInit` con el fichero si el buffer viene relleno |
| `txpowerctrl.cfg` | `rlm_domain.c`, `txPwrCtrlLoadConfig()` (con `CFG_SUPPORT_DYNAMIC_PWR_LIMIT=1`). Igual que el anterior: mete antes la lista con la tabla compilada `g_au1TxPwrDefaultSetting` y luego intenta el cfg; si no está, solo avisa por log a nivel INFO |

Los dos son opcionales en el sentido de que sin ellos el firmware arranca igual con los valores
compilados, pero como los instalamos, se usan: en lo que se pierde es en la calibración y la
configuración de fábrica (tiempo de baliza, offset de canal secundario, límites de potencia).

Los dos buscan también en `/data/misc/wifi/` y `/storage/sdcard0/`, por si acaso.

Que la lista de la MR de firmware del autor (`mt6785-mainline/firmware` !1: *"WMT_SOC.cfg +
wifi.cfg + soc1_0 ram/patch (mcu/bt/wifi) + WIFI_RAM_CODE"*) incluya `wifi.cfg` no dice nada de si
hace falta: es la lista de lo que había en el device original, y ese fichero está en el mismo
cajón que los que sí se leen.

No hace falta EEPROM de calibración: el driver lo pide como `CFG_EEPRM_FILENAME_MT%x.bin`, y si el
fichero no está cae al **modo eFuse** (`ucSourceMode = 0`), que es lo normal en un móvil.

### El wifi: verificado por su autor, sin probar por nosotros

Merece la pena ser preciso, porque "nunca se ha ejecutado" y "nadie lo ha ejecutado" son
afirmaciones muy distintas para este driver.

- **El driver funciona en este móvil, y lo verificó quien lo escribió.** El forward-port es el MR
  !2 de `mt6785-mainline/linux` (*"Draft: begonia (MT6785): conn/WiFi vendor forward-port"*), de
  **minorum**: su descripción afirma que `wlan0` escanea y se asocia en 2.4 y 5 GHz, con DHCP y ping
  verificados en hardware. El historial encaja con eso: el commit `b8c1b8b5` ("Verified on
  hardware: this clears the 'no hif info' gate; STP/BTIF now activates") y los volcados de registros
  en vivo de `0468921f` son apuntes de bring-up, no teoría. Nuestro kernel es la punta de esa serie
  (`3a1ea76942`).
- **Fuera de ese bring-up, nadie ha probado este stack en un begonia.** El MR !2 no tiene ni un
  comentario y nadie ha contestado, así que no hay un segundo informe de nadie. Es un MR
  *cross-fork* (del fork del autor, `minorum/linux`, a `mt6785-mainline/linux`) y lleva desde junio
  de 2026 sin que nadie lo mueva, que es lo razonable para una importación de fabricante de ~545k
  líneas etiquetada como *"not proposing merge yet"*. Somos los primeros en probarlo en pmOS con
  este empaquetado, y los primeros en llevarlo a Kupfer.
- El `RUNTIME-UNPROVEN` que sí aparece en el árbol es **más estrecho y más antiguo** que todo eso,
  y no está en ningún fichero de este port: está en el fichero del kernel que el fwport añade para
  el trigger, `drivers/misc/mediatek/connectivity/common/common_main/linux/wmt_wifi_trigger.c:16`,
  como una nota para quien lo porte: *"compile/link verified only ... the end-to-end bring-up has
  not been exercised on a device"*, y solo duda del **orden** del `func_on`. Su commit
  `ac488ea5` es del 18/06 a las 02:27; los verificados en hardware, `b8c1b8b5` (08:18) y
  `0468921f` (09:25), son de ese mismo día. Sencillamente no se actualizó el comentario.
- Una preocupación que miré y descarté: `WIFI_EINT` y los pines `gpio_combo_*` faltan en el DTS,
  pero pertenecen al camino reimpl ya retirado (`MTK_CONNINFRA_MT6785`, que el MR !2 apaga a
  propósito por conflicto con el consys de fabricante), no al forward-port que corre. Esa lectura es
  mía, no del autor.

### Por qué el Bluetooth interno no se puede

No es un problema de configuración: **falta el driver**. No hay ningún blob de firmware ni ningún
servicio que lo arregle. Y conviene no confundir "el Bluetooth no funciona" con "el Bluetooth no está
portado a medias":

Lo que sí está, y es bastante:

- El móvil lleva el **mismo BTIF que usa el wifi que funciona**. El MCU de conectividad, el canal de
  control WMT y el transporte STP son un stack único, y en begonia el transporte STP vivo *es* el
  BTIF (todo el tráfico sale por `mtk_wcn_btif_write`). Por eso `mtk-vendor-btif` no es un
  transportador genérico: es el mismo camino que usa el `wmt_drv` que ya funciona.
- El nodo DT está en mainline y viene **habilitado por defecto**: `btif@1100c000`
  (`compatible = "mediatek,btif"`, tres rangos `reg`, IRQs 138/155/154, clocks `btifc`/`apdmac`) en
  `arch/arm64/boot/dts/mediatek/mt6785.dtsi`. Nuestro módulo lo enlaza, el blob de BT
  (`soc1_0_ram_bt_2a_1_hdr.bin`) está en la imagen, y `BGF_EINT` (`GIC_SPI 321`) también está
  cableado en el DTS de begonia.

Lo que falta es la **capa HCI**, el driver que leería ese transporte y se lo entregaría a BlueZ. Nada
en `drivers/bluetooth/` consume el BTIF, y no hay ninguna llamada a `hci_register_dev()` en todo
`drivers/misc/mediatek/`: no existe `hci0`, se carguen los módulos como se carguen. `btmtk.c` es solo
la biblioteca compartida (`EXPORT_SYMBOL_GPL`), no registra ningún HCI.

Las dos vías que podrían parecer un atajo se descartan solas:

- `btmtkuart.c` es el único driver HCI de MediaTek del árbol, pero maneja un chip de BT **externo**
  por un UART de verdad (`mt7622`, `mt7663u`, `mt7668u`: SoCs de router; el móvil no lleva ninguno
  integrado), y el `btif` del móvil no es un UART, así que su extensión de línea de comandos ni
  llega a activarse. `btmtksdio.c` es para `mt7921s`, otro caso distinto.
- El `userspace` vendor `mtk_bt_stack` no es redistribuible, y el shim 8250-BTIF al estilo vendor
  (`8250_btif` + `btmtkuart_hci`) se propuso en 2017 y nunca entró en mainline.

**El BT usable es el de un dongle USB** (`btusb`). El blob `soc1_0_ram_bt` se queda en la imagen
porque forma parte del set que carga el bring-up de wifi, no porque sirva para algo hoy.

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

Conclusión: **con este kernel tal cual (sin `mtk_gen4m`) no hay WiFi**, porque el
forward-port del stack vendor existe en el árbol pero está `default n` en Kconfig. Ver abajo.

## El stack de conectividad está en el MISMO commit que ya compilamos

Dato que cambia las cuentas: la rama **`begonia-conn-wifi`** del fork `minorum/linux` apunta a
`3a1ea7694219eb2fd513f0e630f2a882eab5c86f`, que es exactamente el `_tag` que buildea nuestro
APKBUILD. O sea que **no hace falta ni otro kernel ni el MR !8852 (7.1)** para tener
touch + WiFi:

| Módulo | Origen en el árbol | Qué es |
|---|---|---|
| `wmt_drv.ko` | `drivers/misc/mediatek/connectivity/common/` | WMT/STP/connsys bring-up (stage-1), crea `/dev/wmtdetect` y hace el handshake del conn-MCU |
| `wlan_gen4m.ko` | `drivers/misc/mediatek/connectivity/wlan/gen4m/` | WLAN fullmac cfg80211 (stage-2), registra `wlan0`; 93 TU, subset CONNAC/AXI/6785 |
| `mtk-vendor-btif.ko` | `drivers/misc/mediatek/btif/common/` | BTIF: lleva el tráfico de control WMT al conn-MCU. **No aporta HCI**, así que el Bluetooth interno sigue sin poder: ver [Por qué el Bluetooth interno no se puede](#por-qué-el-bluetooth-interno-no-se-puede) |

Kconfig: `MTK_WMT_FWPORT` (padre) → `MTK_WMT_DRV`, `MTK_WLAN_GEN4M`, `MTK_WMT_FWPORT_BTIF`.
Los cuatro están `default n`, y `enable_kernel_drivers.sh` los activa con `mtk_gen4m=1`
(además de `CONFIG_CFG80211_WEXT=y`, que es el símbolo que hace `select WEXT_CORE`; ver
[arriba](#mtk_gen4m-por-qué-está-desactivado-por-defecto) para por qué poner `WEXT_CORE` a mano
no vale).

El DTS de 6.16.4 de la rama ya trae lo necesario: nodo `connectivity-combo`
(`GIC_SPI 321` = BGF_EINT) y las reservas de memoria `consys@ab000000` (4 MB) y
`wifi-reserve-memory`.

### Por qué el touch Tianma no obliga al kernel 7.1

El MR !8852 (kernel 7.1 + split CSOT/Tianma) resuelve el panel, pero en 6.16.4 el touch Tianma ya
funciona con el swap de firmware de la sección de arriba (`nt36672a_begonia_tianma.bin` copiado
con el nombre que espera el DTB). Con 6.16.4 + `mtk_gen4m=1` se tienen touch, WiFi y BT a la vez.

### Lo que puede fallar (leído en el propio código, no hay tests)

1. El Kconfig se describe a sí mismo como *"work-in-progress bring-up vehicle, not an
   upstreamable driver"*.
2. En el DTS, el `WIFI_EINT` del nodo `connectivity-combo` es un **placeholder**
   (`GIC_SPI 78`, sin sourcear del DT de stock) y los pines `gpio_combo_*` se omiten
   (`DEFAULT_PIN_ID`). Si el IRQ no es el real, el WLAN no llega a dar señal.
3. `wmt_drv` trae `wmt_wifi_trigger.o` (*"/dev/wmtWifi WiFi on/off trigger"*), o sea que
   puede hacer falta un trigger de userspace para encender la radio.
4. El transporte STP vivo es BTIF (`stp_uart`/`stp_sdio` están eliminados a propósito: *"dead on
   this SoC"*), así que el puente BTIF↔BlueZ es la parte que no está en el árbol. El kernel trae
   además una reimplementación (`CONFIG_MTK_BTIF` → `mtk-btif.ko`) con el mismo compatible
   `mediatek,btif`: solo una de las dos puede hacer de puente HCI.

Por eso el workflow tiene un check de **señal positiva** (*Verify MTK connectivity modules in
rootfs*): con `mtk_gen4m=1` exige los tres `.ko` en `/usr/lib/modules/**/mediatek/`, para que
un kernel que se compiló sin ellos no pase por verde.

## Errores que no hay que repetir

- **Un `APKBUILD` sobrepuesto con la MISMA versión que la publicada no se
  construye: apk usa la del repo.** Es la trampa más cara de este workflow,
  porque no da ningún error. El `device-xiaomi-begonia` sobrepuesto solo
  cambiaba la lista de `depends` (le añadía
  `firmware-xiaomi-begonia-connectivity`) y se quedó en `6-r0`, la misma
  versión que hay publicada en `edge`, así que apk instaló la del repo y la
  dependencia nueva desapareció sin quejarse. El subpaquete `connectivity` sí se
  construía (766,5 KB, se ve en el log) pero al no depender de él nadie lo
  instalaba, y la imagen salía **verde, arrancaba y no tenía ni un blob en
  `/lib/firmware/mediatek/`**: justo lo que `wlan_gen4m` necesita para pedir
  firmware por `request_firmware()`, o sea que `wlan0` no podía aparecer nunca.
  Lo delata `/lib/apk/db/installed` (el `D:` de `device-xiaomi-begonia` sin
  `-connectivity`). **Regla: cualquier cambio de `depends` en un APKBUILD
  sobrepuesto va con `pkgrel` subido.** El `firmware-xiaomi-begonia` se
  construía bien solo porque su `pkgver` (20260617) es más nuevo que el
  publicado (20250810). Y el `pkgrel` era lo único que ocultaba el
  `sha512sums` roto de abajo: con `pkgrel=0` el paquete no llegaba a
  compilarse nunca, así que su hash jamás se comprobaba.
- **El `sha512sums` de un APKBUILD sobrepuesto hay que rehacerlo, y solo se
  comprueba si el paquete se construye de verdad.** `deviceinfo`,
  `kernel-cmdline.conf` y `modules-initfs` son ficheros del propio árbol (no
  descargas), pero el `sha512sums` que trae el APKBUILD de pmaports es el de
  **los suyos**, y nuestro `deviceinfo` está modificado (sector 4096 +
  `deviceinfo_flash_sparse`), así que el hash es otro. Al subir `pkgrel` a 1 el
  paquete sí se compiló y el run `36307235048` murió en
  `/home/pmos/build/deviceinfo: FAILED` →
  `>>> ERROR: device-xiaomi-begonia: Use 'abuild checksum' to generate/update the checksum(s)`.
  El error dice literalmente qué hacer, pero ojo: `abuild checksum` dentro de
  pmbootstrap necesita el chroot y es un paso lento. Por eso el hash bueno está
  escrito a mano en el APKBUILD **y** hay un paso de CI,
  `Recompute sha512sums of the local device files`
  (`.github/scripts/fix-device-checksums.py`), que reescribe el bloque en la
  *copia* del APKBUILD dentro del árbol de pmaports del runner y luego lo
  verifica con `sha512sum -c`. Así editar `deviceinfo` no puede volver a tumbar
  el build. El mismo aviso aplica a `kernel-cmdline.conf` y `modules-initfs` si
  se tocan.
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
- **Meter `pahole` en makedepends enciende BTF y rompe el build.** El config de pmaports trae
  `CONFIG_DEBUG_INFO_BTF=y`, pero ese símbolo depende de `CONFIG_PAHOLE_HAS_SPLIT_BTF`, que kconfig
  deduce de si **`pahole` está instalado**. Al añadir `pahole` (que es lo que hace upstream desde el
  MR !9035) se activa el build de los host-tools de BTF, y en este paquete `tools/bpf/resolve_btfids`
  se compila con `$CC` (el compilador cruzado) en vez de con `$HOSTCC`, así que no encuentra las
  cabeceras de arch y revienta a los ~4 min, antes incluso de compilar vmlinux:
  ```
  tools/include/linux/types.h:13:10: fatal error: asm/types.h: No such file or directory
  make[5]: *** [tools/build/Makefile.build:86: .../exec-cmd.o] Error 1
  ```
  Es el tipo de fallo que se camufla: el run anterior (sin `pahole`) compiló el kernel
  entero y en su log `resolve_btfids` aparece **0 veces**. Depender de "si pahole está o no" es
  frágil, así que `enable_kernel_drivers.sh` borra las líneas `=y` heredadas y deja
  `# CONFIG_DEBUG_INFO_BTF is not set`, con verificación que aborta si BTF sigue activo. BTF solo
  lleva información de tipos para eBPF/CO-RE: no afecta a arranque, display, wifi, bt ni ethernet.
- **Un backtick en un string con comillas dobles ejecuta código, también dentro de un `for` de
  configuración.** El comentario que explicaba el `menuconfig` padre de RTW88 iba dentro del
  `for line in ...` como `"# ... viven dentro de \`if RTW88\` ..."`, y bash interpretó los backticks
  como command substitution: `if RTW88` no es un comando, así que el error de sintaxis abortó **solo
  ese `for`** (los 21 dongles) y el script siguió con `exit 0`. El `.config` se quedaba sin
  `USB_NET_*`/`RTL8XXXU`/`RTW88*`/`MT76*` y el fallo solo aparecía 40 minutos después, en el verify
  de módulos, con 21 errores `el rootfs no trae <dongle>.ko` que no señalan el culpable.
  `bash -n` **no** lo detecta (los backticks en comillas dobles son sintaxis válida); el workflow
  hace ahora `bash -n` más un `grep` que rechaza backticks fuera de comentarios antes de ejecutarlo.
- **No swapear solo el kernel** (6.16 → 7.1) sin regenerar el initramfs: los `.ko` del initramfs llevan `vermagic` de 6.16 y el kernel 7.1 no los carga → sin display/touch. Por eso se hace build completo con pmbootstrap.
- **`flags=0` en vbmeta** → LK rechaza el boot (bootloop a fastboot). Usar `flags=2`.
- **`kernel = tianma`** es obligatorio; con el default (`stable`) falla porque el device ya no depende directo del kernel (solo expone las subpackages `-kernel-csot`/`-kernel-tianma`).
- **No correr el flasheo con el teléfono en otra variante**: verificar qué panel tiene antes (CSOT vs Tianma).

## Referencias

Lo nuestro:

- MR !8852: https://gitlab.postmarketos.org/postmarketOS/pmaports/-/merge_requests/8852
- Wiki pmOS begonia: https://wiki.postmarketos.org/wiki/Xiaomi_Redmi_Note_8_Pro_(xiaomi-begonia)
- Dispositivos: `pmaports/device/testing/{device,firmware}-xiaomi-begonia` y
  `linux-postmarketos-mediatek-mt6785` (el paquete de kernel de este repo es ese, pineado a un
  commit)

Lo del driver de conectividad, que **no es nuestro** (de ahí vienen el forward-port y los 7 blobs,
y de ahí el crédito):

- Kernel: https://gitlab.postmarketos.org/mt6785-mainline/linux, MR **!2** *"Draft: begonia (MT6785):
  conn/WiFi vendor forward-port"*, de **minorum**, MR *cross-fork*: rama `begonia-conn-wifi` en su
  fork `https://gitlab.postmarketos.org/minorum/linux` (id 1492) → `6.16` en el upstream (id 780).
  La cabeza de esa rama, `3a1ea76942`, es el commit que buildea nuestro APKBUILD; el `6.16` del
  fork se quedó en `203a993f`, que es el tag base de pmaports (y por eso el paquete de pmaports
  solo no trae el stack de conectividad)
- Firmware: https://gitlab.postmarketos.org/mt6785-mainline/firmware, MR **!1** del mismo autor
- Espejo en GitHub: https://github.com/external-mirrors/mt6785-mainline-linux (ramas `6.16`, `7.1`,
  `battery-downstream`)
- Para contrastar con otro SoC del mismo connsys: https://github.com/hataketsu/mt6768-mainline-notes
  (Redmi 9 / MT6768), donde el fwport de gen4m compila pero nunca se ha ejecutado
