#!/bin/bash
# linux_health_v2.sh - SSH Script v2 Sensor (JSON-Schema Version 3)
# Sammelmetriken einer Linux-VM, die die v2-Standardsensoren nicht abdecken.
# Parameter 1: Warnschwelle Benutzer (Standard 5)

WARN_USERS="${1:-5}"

# --- Messwerte einsammeln ------------------------------------------------
USERS=$(who 2>/dev/null | wc -l)
PROCS=$(ps -e --no-headers 2>/dev/null | wc -l)
ZOMBIES=$(ps -eo stat --no-headers 2>/dev/null | grep -c '^Z')

read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg
CORES=$(nproc 2>/dev/null || echo 1)
# Load pro Kern in Prozent (100 % = alle Kerne voll)
LOAD_PCT=$(awk -v l="$LOAD1" -v c="$CORES" 'BEGIN { printf "%.0f", l / c * 100 }')

# Speicher: "verfügbar" ist die ehrliche Zahl, nicht "frei"
MEM_TOTAL=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
MEM_AVAIL=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
MEM_PCT=$(( (MEM_TOTAL - MEM_AVAIL) * 100 / MEM_TOTAL ))

SWAP_TOTAL=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
SWAP_FREE=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)
if (( SWAP_TOTAL > 0 )); then
    SWAP_PCT=$(( (SWAP_TOTAL - SWAP_FREE) * 100 / SWAP_TOTAL ))
else
    SWAP_PCT=0
fi

# Vollster Mountpoint (ohne tmpfs/devtmpfs/squashfs), in Prozent
DISK_PCT=$(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null \
           | awk 'NR>1 { gsub("%","",$5); if ($5+0 > max) max = $5+0 } END { print max+0 }')

TCP_EST=$(ss -tn state established 2>/dev/null | tail -n +2 | wc -l)
UPTIME=$(awk '{print int($1)}' /proc/uptime)

# --- Status bestimmen ----------------------------------------------------
STATUS="ok"; NOTES=()
if (( DISK_PCT >= 95 )); then STATUS="error";   NOTES+=("Disk ${DISK_PCT}%"); fi
if (( DISK_PCT >= 85 && DISK_PCT < 95 )); then STATUS="warning"; NOTES+=("Disk ${DISK_PCT}%"); fi
if (( MEM_PCT >= 90 ));  then [[ $STATUS == ok ]] && STATUS="warning"; NOTES+=("RAM ${MEM_PCT}%"); fi
if (( SWAP_PCT >= 50 )); then [[ $STATUS == ok ]] && STATUS="warning"; NOTES+=("Swap ${SWAP_PCT}%"); fi
if (( LOAD_PCT >= 200 )); then [[ $STATUS == ok ]] && STATUS="warning"; NOTES+=("Load ${LOAD_PCT}%"); fi
if (( ZOMBIES > 0 ));    then [[ $STATUS == ok ]] && STATUS="warning"; NOTES+=("${ZOMBIES} Zombies"); fi
if (( USERS >= WARN_USERS )); then [[ $STATUS == ok ]] && STATUS="warning"; NOTES+=("${USERS} Benutzer"); fi

if (( ${#NOTES[@]} == 0 )); then
    MESSAGE="OK - ${USERS} Benutzer, ${PROCS} Prozesse, Load ${LOAD1}, RAM ${MEM_PCT}%, Disk ${DISK_PCT}%"
else
    MESSAGE="$(IFS=', '; echo "${NOTES[*]}")"
fi

# --- JSON ausgeben -------------------------------------------------------
cat <<EOF
{
  "version": 3,
  "status": "${STATUS}",
  "message": "${MESSAGE}",
  "channels": [
    { "id": 10, "name": "Active Users",        "type": "integer", "kind": "count",        "value": ${USERS},
      "limits": { "warning": { "upper": $((WARN_USERS - 1)) } } },
    { "id": 11, "name": "Processes",           "type": "integer", "kind": "count",        "value": ${PROCS} },
    { "id": 12, "name": "Zombie Processes",    "type": "integer", "kind": "count",        "value": ${ZOMBIES},
      "limits": { "warning": { "upper": 0 } } },
    { "id": 13, "name": "Load 1 min",          "type": "float",   "kind": "custom",       "value": ${LOAD1}, "display_unit": "" },
    { "id": 14, "name": "Load 5 min",          "type": "float",   "kind": "custom",       "value": ${LOAD5}, "display_unit": "" },
    { "id": 15, "name": "Load 15 min",         "type": "float",   "kind": "custom",       "value": ${LOAD15}, "display_unit": "" },
    { "id": 16, "name": "Load per Core",       "type": "integer", "kind": "percent",      "value": ${LOAD_PCT},
      "limits": { "warning": { "upper": 199 } } },
    { "id": 17, "name": "Memory Used",         "type": "integer", "kind": "percent",      "value": ${MEM_PCT},
      "limits": { "warning": { "upper": 89 } } },
    { "id": 18, "name": "Swap Used",           "type": "integer", "kind": "percent",      "value": ${SWAP_PCT},
      "limits": { "warning": { "upper": 49 } } },
    { "id": 19, "name": "Fullest Mount",       "type": "integer", "kind": "percent",      "value": ${DISK_PCT},
      "limits": { "warning": { "upper": 84 }, "error": { "upper": 94 } } },
    { "id": 20, "name": "TCP Established",     "type": "integer", "kind": "count",        "value": ${TCP_EST} },
    { "id": 21, "name": "Uptime",              "type": "integer", "kind": "time_seconds", "value": ${UPTIME} }
  ]
}
EOF
