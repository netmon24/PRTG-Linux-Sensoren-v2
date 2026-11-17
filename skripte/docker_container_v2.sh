#!/bin/bash
# docker_container_v2.sh <containername> - SSH Script v2 Sensor (JSON-Schema Version 3)
# Metriken eines einzelnen Containers: Status, CPU, RAM, Netz, Disk-I/O, PIDs, Restarts, Uptime.
D="/usr/bin/sudo -n /usr/bin/docker"
C="$1"
[[ -z "$C" ]] && read -r -t 2 C
[[ -z "$C" ]] && C="${prtg_parameters:-}"
C="${C//\"/}"

[[ -z "$C" ]] && { printf '{"version":3,"status":"error","message":"Containername als Parameter fehlt"}\n'; exit 0; }

INSPECT=$($D inspect -f '{{.State.Status}}|{{.State.ExitCode}}|{{.State.StartedAt}}|{{.RestartCount}}|{{if .State.Health}}{{with index .State "Health"}}{{.Status}}{{else}}none{{end}}{{else}}none{{end}}' "$C" 2>/dev/null) \
  || { printf '{"version":3,"status":"error","message":"Container %s nicht gefunden"}\n' "$C"; exit 0; }
IFS='|' read -r STATE EXITCODE STARTED RESTARTS HEALTH <<< "$INSPECT"

tobytes() { sed 's/B$//;s/i$//' <<< "${1:-0}" | numfmt --from=si 2>/dev/null || echo 0; }

# Laufzeitmetriken nur bei laufendem Container
CPU=0; MEM_USED=0; MEM_LIMIT=0; MEM_PCT=0; NET_RX=0; NET_TX=0; BLK_R=0; BLK_W=0; PIDS=0; UPTIME=0
if [[ "$STATE" == "running" ]]; then
  STATS=$($D stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}|{{.PIDs}}' "$C" 2>/dev/null)
  IFS='|' read -r CPU MEMU MEMP NET BLK PIDS <<< "$STATS"
  CPU=${CPU%\%}; MEM_PCT=${MEMP%\%}
  MEM_USED=$(tobytes "$(cut -d'/' -f1 <<< "$MEMU" | tr -d ' ')")
  MEM_LIMIT=$(tobytes "$(cut -d'/' -f2 <<< "$MEMU" | tr -d ' ')")
  NET_RX=$(tobytes "$(cut -d'/' -f1 <<< "$NET" | tr -d ' ')")
  NET_TX=$(tobytes "$(cut -d'/' -f2 <<< "$NET" | tr -d ' ')")
  BLK_R=$(tobytes "$(cut -d'/' -f1 <<< "$BLK" | tr -d ' ')")
  BLK_W=$(tobytes "$(cut -d'/' -f2 <<< "$BLK" | tr -d ' ')")
  UPTIME=$(( $(date +%s) - $(date -d "$STARTED" +%s) ))
fi

# Statuscode für den Kanal: 1=running 2=restarting 3=paused 4=exited 5=dead 0=sonstiges
case "$STATE" in running) SC=1;; restarting) SC=2;; paused) SC=3;; exited) SC=4;; dead) SC=5;; *) SC=0;; esac

STATUS="ok"; MSG="${C}: ${STATE}"
if [[ "$STATE" != "running" ]]; then STATUS="error"; MSG="${C} ist ${STATE} (Exit ${EXITCODE})"
elif [[ "$HEALTH" == "unhealthy" ]]; then STATUS="error"; MSG="${C} läuft, Healthcheck unhealthy"
elif [[ "$HEALTH" == "starting" ]]; then STATUS="warning"; MSG="${C} startet (Healthcheck ausstehend)"
else MSG="${C} läuft seit $((UPTIME/3600)) h, CPU ${CPU}%, RAM ${MEM_PCT}%"; fi

cat <<EOF
{ "version": 3, "status": "${STATUS}", "message": "${MSG}",
  "channels": [
    { "id": 10, "name": "State",           "type": "integer", "kind": "custom", "display_unit": "", "value": ${SC},
      "limits": { "error": { "lower": 1, "upper": 1 } } },
    { "id": 11, "name": "Exit Code",       "type": "integer", "kind": "custom", "display_unit": "", "value": ${EXITCODE} },
    { "id": 12, "name": "Restart Count",   "type": "integer", "kind": "count", "value": ${RESTARTS} },
    { "id": 13, "name": "Uptime",          "type": "integer", "kind": "time_seconds", "value": ${UPTIME} },
    { "id": 14, "name": "CPU Usage",       "type": "float",   "kind": "percent_cpu", "value": ${CPU:-0} },
    { "id": 15, "name": "Memory Used",     "type": "integer", "kind": "size_bytes_memory", "value": ${MEM_USED} },
    { "id": 16, "name": "Memory Limit",    "type": "integer", "kind": "size_bytes_memory", "value": ${MEM_LIMIT} },
    { "id": 17, "name": "Memory Usage",    "type": "float",   "kind": "percent", "value": ${MEM_PCT:-0},
      "limits": { "warning": { "upper": 90 } } },
    { "id": 18, "name": "PIDs",            "type": "integer", "kind": "count", "value": ${PIDS:-0} },
    { "id": 19, "name": "Network In",      "type": "counter", "kind": "size_bytes_bandwidth", "value": ${NET_RX} },
    { "id": 20, "name": "Network Out",     "type": "counter", "kind": "size_bytes_bandwidth", "value": ${NET_TX} },
    { "id": 21, "name": "Disk Read",       "type": "counter", "kind": "size_bytes_disk", "value": ${BLK_R} },
    { "id": 22, "name": "Disk Write",      "type": "counter", "kind": "size_bytes_disk", "value": ${BLK_W} }
  ] }
EOF
