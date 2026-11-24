#!/bin/sh
# Run only on an administrator-owned OpenWrt gateway. Local stdout only.
# DHCP leases and station information may include private MAC addresses.
# Never ship this output to an analytics or advertising service.
set -eu
printf '%s\n' '=== DHCP leases (not necessarily currently connected) ==='
if [ -r /tmp/dhcp.leases ]; then
 awk '{printf "expires=%s mac=%s ip=%s hostname=%s\n",$1,$2,$3,$4}' /tmp/dhcp.leases
else
 printf '%s\n' 'DHCP lease file unavailable'
fi
printf '%s\n' '=== Current wireless station inventory ==='
if command -v iw >/dev/null 2>&1; then
 for iface in $(iw dev | awk '$1=="Interface"{print $2}'); do
  printf 'Interface: %s\n' "$iface"
  iw dev "$iface" station dump | awk '/^Station / || /signal:|rx bytes:|tx bytes:|connected time:/'
 done
else
 printf '%s\n' 'iw is unavailable on this router'
fi
