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
  "CONFIG_USB_SERIAL_CP210X=m"; do
  echo "$line" >> "$KCONFIG"
done

echo "=== Verification ==="
grep -E '^(CONFIG_USB_NET|CONFIG_USB_RTL|CONFIG_RTL8|CONFIG_WLAN_VENDOR|CONFIG_MT76|CONFIG_MT792|CONFIG_USB_SERIAL_PL2303|CONFIG_USB_SERIAL_FTDI|CONFIG_USB_SERIAL_CP210)' "$KCONFIG"
