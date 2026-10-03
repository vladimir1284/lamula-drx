#!/usr/bin/env bash
# Deja el enlace cableado al DRx configurado de forma PERMANENTE.
#
# El problema que resuelve: el enlace DRx<->DSP de Z4.6 es punto a punto
# (D-16), asi que en ese cable NO hay servidor DHCP. El perfil que
# NetworkManager crea solo para un interfaz cableado nuevo ("Wired connection
# 1") pide DHCP igual, y en este enlace eso da un bucle eterno de 45 segundos:
#
#   dhcp4 (enp1s0): activation: beginning transaction (timeout in 45 seconds)
#   device (enp1s0): state change: ip-config -> failed (reason 'ip-config-unavailable')
#
# Cada fallo PURGA la direccion del interfaz. Una `ip addr add` a mano no
# sobrevive a eso ni sobrevive a un reinicio, que es como se perdio el soak 5
# del 3-oct-2026.
#
# Lo que deja montado:
#
#   - Perfil `drx-zedboard`: 192.168.1.1/24 estatica, sin pasarela, sin DNS,
#     `never-default`. Las tres cosas importan: este cable no es una salida a
#     Internet y no debe competir con la WiFi por la ruta por defecto ni
#     secuestrar la resolucion de nombres.
#   - IPv6 apagado en este interfaz: el contrato viaja por IPv4 y una direccion
#     de enlace local de mas solo añade ruido de avahi/mDNS.
#   - `Wired connection 1` con autoconnect a no, para que no se active en vez
#     del perfil bueno.
#
# NO toca la WiFi. En esta maquina la WiFi es el camino de SSH, y cambiarla a
# ciegas deja a quien este fuera sin forma de entrar.
#
# Idempotente: se puede correr las veces que haga falta.
#
# Uso:  sudo tools/net_drx_link.sh [interfaz]
set -euo pipefail

ifname="${1:-enp1s0}"
perfil="drx-zedboard"
direccion="192.168.1.1/24"

if [[ "$(id -u)" != "0" ]]; then
    echo "error: hace falta root (NetworkManager no deja escribir perfiles si no)" >&2
    echo "       sudo $0 $ifname" >&2
    exit 1
fi

if ! command -v nmcli >/dev/null 2>&1; then
    echo "error: no hay nmcli; esta maquina no usa NetworkManager" >&2
    exit 1
fi

if ! ip link show "$ifname" >/dev/null 2>&1; then
    echo "error: el interfaz $ifname no existe" >&2
    ip -br link >&2
    exit 1
fi

# Guarda: si la ruta por defecto sale por este interfaz, configurarlo como
# enlace punto a punto deja la maquina sin salida -- y si quien lo corre esta
# por SSH, sin sesion. Parar antes de tocar nada.
if ip route show default | grep -q "dev $ifname"; then
    echo "error: la ruta por defecto sale por $ifname. Este script lo quiere" >&2
    echo "       dedicado al DRx, no a la LAN. Comprueba el cableado." >&2
    exit 1
fi

if nmcli -t -f NAME connection show | grep -qx "$perfil"; then
    echo "perfil $perfil ya existe, actualizando"
    nmcli connection modify "$perfil" \
        connection.interface-name "$ifname" \
        ipv4.method manual \
        ipv4.addresses "$direccion" \
        ipv4.gateway "" \
        ipv4.dns "" \
        ipv4.never-default yes \
        ipv6.method disabled \
        connection.autoconnect yes \
        connection.autoconnect-priority 10
else
    echo "creando perfil $perfil"
    nmcli connection add type ethernet ifname "$ifname" con-name "$perfil" \
        ipv4.method manual \
        ipv4.addresses "$direccion" \
        ipv4.never-default yes \
        ipv4.dns "" \
        ipv6.method disabled \
        connection.autoconnect yes \
        connection.autoconnect-priority 10
fi

# El perfil por defecto de NetworkManager es el que mete el bucle de DHCP. No
# se borra -- si alguien enchufa este puerto a una LAN de verdad lo va a
# querer -- pero deja de activarse solo.
if nmcli -t -f NAME connection show | grep -qx "Wired connection 1"; then
    nmcli connection modify "Wired connection 1" connection.autoconnect no
    echo "'Wired connection 1' ya no se autoconecta"
fi

nmcli connection up "$perfil" >/dev/null
echo
ip -br addr show "$ifname"
echo
echo "enlace del DRx listo. La placa escucha en 192.168.1.10:9470 (contrato v0.8)."
