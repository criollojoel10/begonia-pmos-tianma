#!/bin/sh
# Enciende el wifi interno de MediaTek (begonia, MT6785).
#
# El chip no se despierta solo: hay que cargar los tres modulos del fwport y
# escribir un '1' en /dev/wmtWifi, que es el interruptor que le pide al conn-MCU
# que arranque el firmware del wifi. El orden importa: el write pasa por
# wmt_dev_set_hif_btif(), que necesita el transporte BTIF ya registrado.
#
# Verificado en un begonia con el wifi asi conectado: se escanea en 2.4 y 5 GHz
# y se asocia con DHCP. El driver lo verifico su autor (minorum) en hardware.
set -eu

log() { echo "mediatek-wifi: $*"; }

# El modulo base carga mtk-vendor-btif como dependencia, pero lo pedimos
# explicito para que el orden quede claro y para no depender de eso.
log "cargando mtk-vendor-btif"
modprobe mtk-vendor-btif

log "cargando wmt_drv"
modprobe wmt_drv

# wmt_drv crea /dev/wmtWifi al arrancar. Sin esto, el firmware no se pide.
i=0
while [ ! -e /dev/wmtWifi ]; do
	i=$((i + 1))
	[ "$i" -gt 30 ] && { log "ERROR: /dev/wmtWifi no apareció"; exit 1; }
	sleep 1
done
log "/dev/wmtWifi listo"

log "cargando wlan_gen4m"
modprobe wlan_gen4m

log "encendiendo la funcion wifi del conn-MCU"
printf 1 > /dev/wmtWifi

# El netdev lo crea el driver al terminar el arranque del firmware.
i=0
while [ ! -e /sys/class/net/wlan0 ]; do
	i=$((i + 1))
	[ "$i" -gt 20 ] && { log "AVISO: wlan0 no apareció; revisa dmesg | grep -i connac"; exit 0; }
	sleep 1
done
log "wlan0 presente; que NetworkManager se encargue de la conexion"
