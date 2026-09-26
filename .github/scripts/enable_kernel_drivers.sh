#!/bin/bash
# Enable USB Ethernet & WiFi dongle drivers in begonia kernel config
set -euo pipefail

KCONFIG="${PMAPORTS_DIR}/device/testing/linux-postmarketos-mediatek-mt6785/config-postmarketos-mediatek-mt6785.aarch64"

echo "=== Current USB/WiFi config ==="
grep -E '^(CONFIG_USB_NET|CONFIG_USB_RTL|CONFIG_RTL8|CONFIG_WLAN_VENDOR|CONFIG_MT76|CONFIG_USB_SERIAL_PL2303|CONFIG_USB_SERIAL_FTDI|CONFIG_USB_SERIAL_CP210)' "$KCONFIG" || echo "No USB net dongles enabled"

echo "=== Enabling USB Ethernet dongle drivers ==="
for line in \
  "# USB Ethernet dongles (hub USB-C)" \
  "CONFIG_USB_USBNET=y" \
  "CONFIG_USB_NET_AX8817X=m" \
  "CONFIG_USB_NET_AX88179_178A=m" \
  "CONFIG_USB_RTL8150=m" \
  "CONFIG_USB_RTL8152=m" \
  "CONFIG_USB_NET_CDCETHER=m" \
  "CONFIG_USB_NET_CDC_EEM=m" \
  "CONFIG_USB_NET_CDC_NCM=m" \
  "CONFIG_USB_NET_DM9601=m" \
  "CONFIG_USB_NET_SMSC95XX=m" \
  "CONFIG_USB_NET_SR9700=m" \
  "CONFIG_USB_NET_SR9800=m" \
  "" \
  "# Wi-Fi Realtek (cubre TP-Link W821N: RTL8188EU / RTL8192EU)" \
  "CONFIG_WLAN_VENDOR_REALTEK=y" \
  "CONFIG_RTL8XXXU=m" \
  "" \
  "# Wi-Fi MediaTek" \
  "CONFIG_WLAN_VENDOR_MEDIATEK=y" \
  "CONFIG_MT76=m" \
  "CONFIG_MT76_USB=m" \
  "CONFIG_MT76X0U=m" \
  "CONFIG_MT76X2U=m" \
  "CONFIG_MT7921U=m" \
  "" \
  "# USB-to-Serial adapters" \
  "CONFIG_USB_SERIAL_PL2303=m" \
  "CONFIG_USB_SERIAL_FTDI_SIO=m" \
  "CONFIG_USB_SERIAL_CP210X=m" \
  "" \
  "# Bluetooth USB (Realtek RTL8821C, CSR dongles)" \
  "CONFIG_BT_LE=y" \
  "CONFIG_BT_HCIBTUSB=m" \
  ""; do
  echo "$line" >> "$KCONFIG"
done

# Stack WiFi/BT interno MediaTek (begonia-conn-wifi). Opt-in con MTK_GEN4M=1.
#
# Por defecto OFF: wlan_gen4m.ko llama a wireless_send_event(), que solo se
# compila con CONFIG_WEXT_CORE. Sin esa opcion modpost aborta el build con
#     ERROR: modpost: "wireless_send_event" [.../wlan_gen4m.ko] undefined!
# El wifi por dongle (rtl8xxxu/mt76) no depende de este stack.
if [ "${MTK_GEN4M:-0}" = "1" ]; then
  echo "=== Enabling MTK connectivity stack (wlan interno) ==="
  for line in \
    "CONFIG_WEXT_CORE=y" \
    "CONFIG_MTK_WMT_FWPORT=m" \
    "CONFIG_MTK_WMT_DRV=m" \
    "CONFIG_MTK_WLAN_GEN4M=m" \
    "CONFIG_MTK_WMT_FWPORT_BTIF=m"; do
    echo "$line" >> "$KCONFIG"
  done
  grep -E '^(CONFIG_WEXT_CORE|CONFIG_MTK_WMT|CONFIG_MTK_WLAN)' "$KCONFIG" \
    || { echo "ERROR: no se aplico el stack MTK" >&2; exit 1; }
else
  echo "=== MTK gen4m stack DISABLED (default): wifi via dongle ==="
  # El script es idempotente: si el config ya traia el stack (o una corrida
  # previa lo dejo a medias), se quita por completo. olddefconfig lo
  # descartaria igual, pero dejarlo en el .config confunde la inspeccion.
  sed -i -E '/^CONFIG_(MTK_WMT_FWPORT|MTK_WMT_DRV|MTK_WLAN_GEN4M|MTK_WMT_FWPORT_BTIF)=/d' "$KCONFIG"
  if grep -qE '^CONFIG_(MTK_WMT|MTK_WLAN)' "$KCONFIG"; then
    echo "ERROR: quedaron lineas del stack MTK en $KCONFIG" >&2
    exit 1
  fi
  echo "    (reactivar con MTK_GEN4M=1; ver nota sobre wireless_send_event)"
fi

echo "=== Verification ==="
grep -E '^(CONFIG_USB_NET|CONFIG_USB_RTL|CONFIG_RTL8|CONFIG_WLAN_VENDOR|CONFIG_MT76|CONFIG_MT792|CONFIG_USB_SERIAL_PL2303|CONFIG_USB_SERIAL_FTDI|CONFIG_USB_SERIAL_CP210)' "$KCONFIG"
