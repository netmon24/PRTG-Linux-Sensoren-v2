#!/bin/bash
# os_lifecycle_v2.sh - SSH Script v2 Sensor (JSON-Schema Version 3)
# Meldet Distribution, Tage bis End-of-Life, ausstehende Updates, Reboot-Bedarf.
# Warnung < 180 Tage vor EOL, Fehler ab EOL.
#
# EOL-Tabelle: ID+VERSION_ID -> Datum (YYYY-MM-DD). Debian = Ende LTS, Ubuntu = Ende
# Standard-Support (ohne Pro/ESM), RHEL-Familie = Ende Maintenance. Bei neuen Releases
# hier ergänzen; Stand 09/2026, Daten der jeweiligen Hersteller-Seiten.
declare -A EOL=(
  [debian:10]=2024-06-30  [debian:11]=2026-08-31  [debian:12]=2028-06-30  [debian:13]=2030-06-30
  [ubuntu:20.04]=2025-05-31 [ubuntu:22.04]=2027-06-01 [ubuntu:24.04]=2029-05-31 [ubuntu:26.04]=2031-05-31
  [rhel:8]=2029-05-31 [rhel:9]=2032-05-31 [rhel:10]=2035-05-31
  [almalinux:8]=2029-05-31 [almalinux:9]=2032-05-31 [almalinux:10]=2035-05-31
  [rocky:8]=2029-05-31 [rocky:9]=2032-05-31 [rocky:10]=2035-05-31
)

. /etc/os-release 2>/dev/null
ID="${ID:-unknown}"; VER="${VERSION_ID:-0}"; NAME="${PRETTY_NAME:-$ID $VER}"
KEY="${ID}:${VER}"; [[ -z "${EOL[$KEY]}" && "$ID" =~ ^(rhel|almalinux|rocky)$ ]] && KEY="${ID}:${VER%%.*}"

if [[ -n "${EOL[$KEY]}" ]]; then
  DAYS=$(( ( $(date -d "${EOL[$KEY]}" +%s) - $(date +%s) ) / 86400 ))
  KNOWN=1
else
  DAYS=0; KNOWN=0
fi

# Ausstehende Updates (apt oder dnf), ohne Root
UPD=0; SEC=0
if command -v apt-get >/dev/null; then
  UPD=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst ')
  SEC=$(apt-get -s upgrade 2>/dev/null | grep '^Inst ' | grep -ci 'security')
elif command -v dnf >/dev/null; then
  UPD=$(dnf -q check-update 2>/dev/null | grep -c '^[a-zA-Z0-9]')
  SEC=$(dnf -q updateinfo list security 2>/dev/null | grep -c .)
fi

REBOOT=0; [[ -f /var/run/reboot-required ]] && REBOOT=1
command -v needs-restarting >/dev/null && ! needs-restarting -r >/dev/null 2>&1 && REBOOT=1

STATUS="ok"; MSG="${NAME}"
if (( KNOWN == 0 )); then STATUS="warning"; MSG="${NAME} - EOL-Datum unbekannt, Tabelle im Skript ergaenzen"
elif (( DAYS <= 0 )); then STATUS="error"; MSG="${NAME} ist seit $(( -DAYS )) Tagen End-of-Life (${EOL[$KEY]})"
elif (( DAYS < 180 )); then STATUS="warning"; MSG="${NAME} - EOL in ${DAYS} Tagen (${EOL[$KEY]})"
else MSG="${NAME} - EOL ${EOL[$KEY]}, ${UPD} Updates ausstehend"; fi
(( REBOOT == 1 )) && { [[ $STATUS == ok ]] && STATUS="warning"; MSG="${MSG} - Reboot erforderlich"; }

cat <<EOF
{ "version": 3, "status": "${STATUS}", "message": "${MSG}",
  "channels": [
    { "id": 10, "name": "Days to EOL",      "type": "integer", "kind": "custom", "display_unit": "Tage", "value": ${DAYS},
      "limits": { "warning": { "lower": 180 }, "error": { "lower": 1 } } },
    { "id": 11, "name": "Pending Updates",  "type": "integer", "kind": "count", "value": ${UPD} },
    { "id": 12, "name": "Security Updates", "type": "integer", "kind": "count", "value": ${SEC},
      "limits": { "warning": { "upper": 0 } } },
    { "id": 13, "name": "Reboot Required",  "type": "integer", "kind": "count", "value": ${REBOOT},
      "limits": { "warning": { "upper": 0 } } }
  ] }
EOF
