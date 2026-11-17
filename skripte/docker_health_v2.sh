#!/bin/bash
# docker_health_v2.sh - SSH Script v2 Sensor (JSON-Schema Version 3)
D="/usr/bin/sudo -n /usr/bin/docker"

if ! $D ps -q >/dev/null 2>&1; then
  printf '{"version":3,"status":"error","message":"Docker nicht erreichbar oder sudo-Regel fehlt"}\n'; exit 0
fi

TOTAL=0; RUNNING=0; EXITED=0; RESTARTING=0; PAUSED=0; UNHEALTHY=0; BAD=""
while IFS='|' read -r state status name; do
  ((TOTAL++))
  case "$state" in
    running)     ((RUNNING++)) ;;
    exited|dead) ((EXITED++)) ;;
    restarting)  ((RESTARTING++)); BAD="$BAD $name(restart)" ;;
    paused)      ((PAUSED++)) ;;
  esac
  [[ "$status" == *unhealthy* ]] && { ((UNHEALTHY++)); BAD="$BAD $name(unhealthy)"; }
done < <($D ps -a --format '{{.State}}|{{.Status}}|{{.Names}}')

IMAGES=$($D images -q | sort -u | wc -l)
DANGLING=$($D images -q -f dangling=true | wc -l)

tobytes() { sed 's/B$//' <<< "${1:-0}" | numfmt --from=si 2>/dev/null || echo 0; }
DFLINE=$($D system df --format '{{.Type}}|{{.Size}}|{{.Reclaimable}}' | awk -F'|' '$1=="Images"')
IMG_BYTES=$(tobytes "$(cut -d'|' -f2 <<< "$DFLINE")")
REC_BYTES=$(tobytes "$(cut -d'|' -f3 <<< "$DFLINE" | cut -d' ' -f1)")

STATUS="ok"; MSG="OK - ${RUNNING}/${TOTAL} Container laufen, ${IMAGES} Images"
if (( UNHEALTHY > 0 )); then STATUS="error"; MSG="Problem:${BAD}"
elif (( RESTARTING > 0 )); then STATUS="warning"; MSG="Problem:${BAD}"
elif (( DANGLING > 5 )); then STATUS="warning"; MSG="${DANGLING} dangling Images"; fi

cat <<EOF
{ "version": 3, "status": "${STATUS}", "message": "${MSG}",
  "channels": [
    { "id": 10, "name": "Containers Total",      "type": "integer", "kind": "count", "value": ${TOTAL} },
    { "id": 11, "name": "Containers Running",    "type": "integer", "kind": "count", "value": ${RUNNING} },
    { "id": 12, "name": "Containers Exited",     "type": "integer", "kind": "count", "value": ${EXITED} },
    { "id": 13, "name": "Containers Restarting", "type": "integer", "kind": "count", "value": ${RESTARTING}, "limits": { "warning": { "upper": 0 } } },
    { "id": 14, "name": "Containers Paused",     "type": "integer", "kind": "count", "value": ${PAUSED} },
    { "id": 15, "name": "Containers Unhealthy",  "type": "integer", "kind": "count", "value": ${UNHEALTHY}, "limits": { "error": { "upper": 0 } } },
    { "id": 16, "name": "Images",                "type": "integer", "kind": "count", "value": ${IMAGES} },
    { "id": 17, "name": "Dangling Images",       "type": "integer", "kind": "count", "value": ${DANGLING}, "limits": { "warning": { "upper": 5 } } },
    { "id": 18, "name": "Image Disk Usage",      "type": "integer", "kind": "size_bytes_disk", "value": ${IMG_BYTES} },
    { "id": 19, "name": "Reclaimable Space",     "type": "integer", "kind": "size_bytes_disk", "value": ${REC_BYTES} }
  ] }
EOF
