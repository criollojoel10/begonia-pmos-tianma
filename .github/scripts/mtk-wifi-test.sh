#!/bin/sh
# Prueba del stack WiFi/BT interno de MediaTek (begonia, MT6785).
#
# Vale igual en postmarketOS (busybox ash) y en Kupfer (systemd/coreutils).
# No cambia nada del sistema: solo carga modulos y lee dmesg/proc. Lo unico que
# escribe es /dev/wmtWifi, que es justamente el interruptor del wifi.
#
# Uso: hay que ejecutarlo como root (modprobe y el write a /dev/wmtWifi, que es
# 0660 root:root).
#   scp mtk-wifi-test.sh joel@172.16.42.1:/tmp/
#   ssh joel@172.16.42.1 'sudo sh /tmp/mtk-wifi-test.sh'
#
# Salida esperada si todo va bien: "wlan0" presente, rfkill con el soft/hard
# block en 0 y en dmesg "[wmtWifi] WIFI function ON".
#
# Esto prueba el empaquetado (orden de carga, firmware en su sitio, el trigger),
# no el driver: el driver esta verificado en hardware por su autor (minorum) en un
# begonia, donde wlan0 escanea y se asocia en 2.4/5 GHz con DHCP y ping.

set -u
FAIL=0
say() { printf '\n=== %s\n' "$*"; }
ok()  { printf '  [OK]   %s\n' "$*"; }
bad() { printf '  [FALLO] %s\n' "$*"; FAIL=$((FAIL + 1)); }
info() { printf '  %s\n' "$*"; }

say "entorno"
info "kernel: $(uname -r)  arch: $(uname -m)"
info "init:   $(cat /proc/1/comm 2>/dev/null)  uptime: $(cut -d. -f1 /proc/uptime 2>/dev/null)s"

say "1. modulos de kernel presentes"
for m in wmt_drv wlan_gen4m mtk-vendor-btif; do
	if modinfo "$m" >/dev/null 2>&1; then
		ok "$m ($(modinfo -F filename "$m" 2>/dev/null))"
	else
		bad "$m no instalado (modinfo no lo encuentra)"
	fi
done

say "2. firmware de conectividad"
FW=/usr/lib/firmware/mediatek
[ -d "$FW" ] || FW=/lib/firmware/mediatek
if [ -d "$FW" ]; then
	ok "$FW existe"
	# Los 6 blobs que el driver pide de verdad: wmt_dev.c (WMT_SOC.cfg,
	# soc1_0_patch_mcu), wmt_ctrl.c (soc1_0_ram_{mcu,wifi,bt}) y gl_kal.c
	# (WIFI_RAM_CODE, vía connacConstructFirmwarePrio).
	for f in WMT_SOC.cfg soc1_0_patch_mcu_2a_1_hdr.bin soc1_0_ram_mcu_2a_1_hdr.bin \
		soc1_0_ram_wifi_2a_1_hdr.bin soc1_0_ram_bt_2a_1_hdr.bin WIFI_RAM_CODE_soc1_0_2a_1.bin; do
		if [ -e "$FW/$f" ] || [ -e "$FW/$f.zst" ]; then
			ok "$f"
		else
			bad "$f falta en $FW"
		fi
	done
	# wifi.cfg y txpowerctrl.cfg no hacen falta para que arranque el firmware, y
	# no por un fallback: los dos se cargan con la tabla de fabrica YA COMPILADA
	# puesta antes, y el fichero solo la sobreescribe si viene relleno.
	#   - wlanGetConfig() (gl_init.c:3361), desde wlanOnPreAdapterStart con
	#     CFG_SUPPORT_CFG_FILE=1, hace wlanCfgInit(prAdapter, NULL, 0, 0) y solo
	#     vuelve a llamar wlanCfgInit con el buffer si pucConfigBuf[0] != 0.
	#   - txPwrCtrlLoadConfig() (rlm_domain.c) mete la lista global compilada con
	#     txPwrCtrlGlobalVariableToList() y luego intenta el cfg; si no esta, solo
	#     escribe "no txpowerctrl.cfg or file is empty" a nivel INFO.
	# Los dos proban ademas /data/misc/wifi/ y /storage/sdcard0/ por si acaso.
	# Se listan aparte para saber si estan: nosotros los instalamos, asi que si
	# se pierde alguno se pierde la calibracion de fabrica, no el arranque.
	for f in wifi.cfg txpowerctrl.cfg; do
		if [ -e "$FW/$f" ] || [ -e "$FW/$f.zst" ]; then
			ok "$f (opcional, pero se usara: es la calibracion de fabrica)"
		else
			info "$f ausente: el driver arranca igual con la tabla compilada"
		fi
	done
else
	bad "no existe el directorio de firmware ($FW)"
fi
# Los .zst los descomprime el kernel si CONFIG_FW_LOADER_COMPRESS_ZSTD=y.
if [ -r /proc/config.gz ]; then
	zcat /proc/config.gz 2>/dev/null | grep -q 'FW_LOADER_COMPRESS_ZSTD=y' \
		&& ok "el kernel descomprime .zst" \
		|| info "AVISO: FW_LOADER_COMPRESS_ZSTD no esta activo: descomprime los .zst a mano"
fi

say "3. nodos de la plataforma (DTS)"
for d in wifi@18000000 consys@18002000 btif@1100c000; do
	if [ -d "/sys/bus/platform/devices/$d" ]; then
		ok "$d"
	else
		bad "$d no existe (falta el nodo en el DTS o el kernel)"
	fi
done
if [ -d /sys/bus/platform/devices/wmac@18000000 ]; then
	info "AVISO: wmac@18000000 esta enabled; deberia ser disabled (colisiona con el stack)"
fi

say "4. carga de modulos (orden: btif -> wmt_drv -> wlan_gen4m)"
# El btif va primero: el write a /dev/wmtWifi llama a wmt_dev_set_hif_btif(),
# que necesita el modulo para registrar el transporte STP.
if modprobe mtk-vendor-btif 2>&1; then ok "mtk-vendor-btif cargado"; else bad "modprobe mtk-vendor-btif fallo"; fi
if modprobe wmt_drv 2>&1; then ok "wmt_drv cargado"; else bad "modprobe wmt_drv fallo"; fi
if modprobe wlan_gen4m 2>&1; then ok "wlan_gen4m cargado"; else bad "modprobe wlan_gen4m fallo"; fi

say "5. estado ANTES del trigger"
info "dmesg wmt/connac:"
dmesg 2>/dev/null | grep -iE "wmt|connac|consys|conninfra" | tail -8 | sed 's/^/    /' || info "(nada)"
if [ -e /dev/wmtWifi ]; then
	ok "/dev/wmtWifi existe"
	info "permisos: $(ls -l /dev/wmtWifi)"
else
	bad "/dev/wmtWifi no existe: wmt_drv no registro el nodo"
fi

say "6. trigger: escribir '1' en /dev/wmtWifi"
if [ -e /dev/wmtWifi ]; then
	# printf, no echo: el nodo lee un solo caracter.
	if printf 1 > /dev/wmtWifi 2>/tmp/mtk-trigger.err; then
		ok "write aceptado"
	else
		bad "write fallo: $(cat /tmp/mtk-trigger.err 2>/dev/null)"
	fi
	sleep 8
fi

say "7. estado DESPUES del trigger"
info "dmesg (ultimas lineas relevantes):"
dmesg 2>/dev/null | grep -iE "wmtWifi|connac|consys|wlan|conninfra|mt6785-consys|register" | tail -25 | sed 's/^/    /'
info "errores de firmware:"
dmesg 2>/dev/null | grep -iE "request_firmware|firmware.*fail|failed to load|WMT_SOC" | tail -8 | sed 's/^/    /' || info "(ninguno)"

if [ -d /sys/class/net/wlan0 ]; then
	ok "wlan0 existe"
	ip -o link show wlan0 2>/dev/null | sed 's/^/    /'
	if command -v iw >/dev/null 2>&1; then
		iw dev 2>&1 | sed 's/^/    /'
	else
		info "(iw no esta instalado: no se puede ver el modo de la interfaz)"
	fi
	if command -v rfkill >/dev/null 2>&1; then
		rfkill list 2>/dev/null | grep -i wlan | sed 's/^/    /'
	fi
else
	bad "wlan0 no aparece: el firmware no arranco o el probe no llego a hacer ioctl"
fi

say "8. diagnostico del WMT (proc del driver)"
# El fwport deja instrumentacion propia, y es lo mas util si wlan0 no sale: el
# volcado del estado del chip dice si el problema es el BTIF, el conn-MCU o el
# firmware.
info "dispositivos de clase del stack:"
ls -d /sys/class/*wmt* /dev/stpwmt 2>/dev/null | sed 's/^/    /' || info "    (ninguno: wmt_drv no creo sus dispositivos)"

# Chip id, version del firmware y estado del HIF. Si el chip-id hw_check falla,
# el BTIF no abrio o el conn-MCU no arranco (asi se documento el debug del autor).
if [ -r /proc/driver/wmt_dbg ]; then
	ok "/proc/driver/wmt_dbg"
	head -c 2000 /proc/driver/wmt_dbg 2>/dev/null | sed 's/^/    /'
else
	info "/proc/driver/wmt_dbg no disponible"
fi

if [ -r /proc/driver/wmt_dump_info ]; then
	ok "/proc/driver/wmt_dump_info"
	head -c 4000 /proc/driver/wmt_dump_info 2>/dev/null | sed 's/^/    /'
else
	info "/proc/driver/wmt_dump_info no disponible"
fi

# wmt_aee es el dump de excepcion del propio firmware (buffer de 3072 B): si el
# conn-MCU se cuelga o hace assert, esto dice por que.
if [ -r /proc/driver/wmt_aee ]; then
	ok "/proc/driver/wmt_aee"
	if [ -s /proc/driver/wmt_aee ]; then
		head -c 3072 /proc/driver/wmt_aee 2>/dev/null | sed 's/^/    /'
	else
		info "    (vacio: no hay ninguna excepcion registrada)"
	fi
else
	info "/proc/driver/wmt_aee no disponible"
fi

# wmt_user_proc es write-only (no tiene proc_read), asi que no se puede leer.
# Se deja el comando apuntado y NO se ejecuta: llama a
# mtk_wcn_wmt_func_on(WMTDRV_TYPE_WIFI=3) igual que el trigger, pero sin
# wmt_dev_set_hif_btif(), asi que sin el btif registrado se queda en el mismo
# "no hif info". Solo serviria para confirmar que la llamada llega al conn-MCU, y
# no merece la pena arriesgar el estado del MCU en el unico intento con el movil.
if [ -e /proc/driver/wmt_user_proc ]; then
	info "/proc/driver/wmt_user_proc existe (solo escritura). Para probarlo a mano:"
	info "    echo '0 3 1' > /proc/driver/wmt_user_proc   # 0=func_ctrl 3=WIFI 1=on"
else
	info "/proc/driver/wmt_user_proc no disponible"
fi

say "9. otras interfaces (por si el trigger no hizo nada pero hay dongle)"
ls /sys/class/net | sed 's/^/    /'

say "veredicto"
if [ "$FAIL" -eq 0 ]; then
	info "sin fallos en los pasos 1-6. Si wlan0 no sale, mira el dmesg del paso 7"
	info "y el diagnostico del WMT del paso 8."
else
	info "$FAIL comprobaciones fallidas; el paso 7 y el paso 8 son la pista principal."
fi
echo
echo "Para apagar el wifi de nuevo: printf 0 > /dev/wmtWifi"
