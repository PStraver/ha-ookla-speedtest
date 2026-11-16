#!/usr/bin/env bash
# Ookla Speedtest app voor Home Assistant.
# Draait de officiële Ookla CLI op vaste tijden (of op verzoek via
# hassio.addon_stdin met input "run") en zet de resultaten als sensoren in HA.
set -u

OPTIONS="${OPTIONS_FILE:-/data/options.json}"
DATA_DIR="${DATA_DIR:-/data}"
LAST="${DATA_DIR}/last_result.json"
HA_API="${HA_API:-http://supervisor/core/api}"
SPEEDTEST_BIN="${SPEEDTEST_BIN:-speedtest}"
REPUBLISH_SECONDS="${REPUBLISH_SECONDS:-600}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

opt() { jq -r "$1" "$OPTIONS"; }

# Eén sensor naar Home Assistant sturen.
post_state() {
  local entity="$1" state="$2" attrs="$3"
  local body
  body=$(jq -nc --arg s "$state" --argjson a "$attrs" '{state: $s, attributes: $a}')
  if ! curl -fsS -o /dev/null -X POST \
      -H "Authorization: Bearer ${SUPERVISOR_TOKEN:-}" \
      -H "Content-Type: application/json" \
      -d "$body" "${HA_API}/states/${entity}"; then
    log "Kon ${entity} niet bijwerken in Home Assistant"
    return 1
  fi
}

# Alle sensoren publiceren op basis van het laatste resultaat.
publish() {
  [ -s "$LAST" ] || return 0
  local status
  status=$(jq -r '.status' "$LAST")
  local common
  common=$(jq -c '{
      server: .server, isp: .isp, result_url: .result_url,
      tested_at: .tested_at, status: .status, error: .error }' "$LAST")

  post_state sensor.ookla_speedtest_status "$status" \
    "$(jq -c --argjson c "$common" -n '$c + {friendly_name: "Ookla Speedtest status", icon: "mdi:speedometer"}')"

  if [ "$status" = "ok" ]; then
    local mbit='{unit_of_measurement: "Mbit/s", device_class: "data_rate", state_class: "measurement"}'
    post_state sensor.ookla_speedtest_download "$(jq -r '.download' "$LAST")" \
      "$(jq -c --argjson c "$common" -n "\$c + $mbit + {friendly_name: \"Ookla Speedtest download\", icon: \"mdi:download\"}")"
    post_state sensor.ookla_speedtest_upload "$(jq -r '.upload' "$LAST")" \
      "$(jq -c --argjson c "$common" -n "\$c + $mbit + {friendly_name: \"Ookla Speedtest upload\", icon: \"mdi:upload\"}")"
    post_state sensor.ookla_speedtest_ping "$(jq -r '.ping' "$LAST")" \
      "$(jq -c --argjson c "$common" -n '$c + {unit_of_measurement: "ms", device_class: "duration", state_class: "measurement", friendly_name: "Ookla Speedtest ping", icon: "mdi:timer-outline"}')"
    post_state sensor.ookla_speedtest_jitter "$(jq -r '.jitter' "$LAST")" \
      "$(jq -c --argjson c "$common" -n '$c + {unit_of_measurement: "ms", device_class: "duration", state_class: "measurement", friendly_name: "Ookla Speedtest jitter", icon: "mdi:sine-wave"}')"
  fi
}

# Speedtest uitvoeren en resultaat opslaan.
run_test() {
  if [ "$(opt '.accept_ookla_license')" != "true" ]; then
    log "Licentie van Ookla is niet geaccepteerd (optie accept_ookla_license). Test overgeslagen."
    return 0
  fi
  local server_id args out rc now
  server_id=$(opt '.server_id // ""')
  args=(--accept-license --accept-gdpr --format=json)
  [ -n "$server_id" ] && args+=(--server-id="$server_id")
  now=$(date -Iseconds)
  log "Speedtest gestart ${server_id:+(server ${server_id})}"
  out=$("$SPEEDTEST_BIN" "${args[@]}" 2>/tmp/speedtest.err)
  rc=$?
  if [ $rc -eq 0 ] && echo "$out" | jq -e '.type == "result"' >/dev/null 2>&1; then
    echo "$out" | jq -c --arg now "$now" '{
        status: "ok",
        error: null,
        download: ((.download.bandwidth * 8 / 1000000) * 10 | round / 10),
        upload: ((.upload.bandwidth * 8 / 1000000) * 10 | round / 10),
        ping: ((.ping.latency * 10 | round) / 10),
        jitter: ((.ping.jitter * 10 | round) / 10),
        server: ((.server.name // "") + " - " + (.server.location // "")),
        isp: (.isp // null),
        result_url: (.result.url // null),
        tested_at: $now }' > "$LAST.tmp" && mv "$LAST.tmp" "$LAST"
    log "Klaar: $(jq -r '"\(.download) Mbit/s down, \(.upload) Mbit/s up, \(.ping) ms ping (\(.server))"' "$LAST")"
  else
    local err
    err=$( (echo "$out" | jq -r '.error // empty' 2>/dev/null; cat /tmp/speedtest.err) | tr '\n' ' ' | cut -c1-250)
    log "Speedtest mislukt: ${err:-onbekende fout}"
    # Vorige meetwaarden bewaren, alleen status op fout zetten.
    if [ -s "$LAST" ]; then
      jq -c --arg e "${err:-onbekende fout}" --arg now "$now" '.status = "fout" | .error = $e | .tested_at = $now' "$LAST" > "$LAST.tmp" && mv "$LAST.tmp" "$LAST"
    else
      jq -nc --arg e "${err:-onbekende fout}" --arg now "$now" '{status: "fout", error: $e, server: null, isp: null, result_url: null, tested_at: $now}' > "$LAST"
    fi
  fi
  publish
}

# Opdrachten via stdin (service hassio.addon_stdin, input: "run").
listen_stdin() {
  while read -r line; do
    case "$(echo "$line" | tr -d '"' | tr '[:upper:]' '[:lower:]')" in
      run|test|start) log "Test op verzoek"; run_test ;;
      *) log "Onbekende opdracht: $line" ;;
    esac
  done
}

# Tijdzone van Home Assistant overnemen, zodat de geplande tijden lokale tijd zijn.
set_timezone() {
  local tz
  tz=$(curl -fsS -H "Authorization: Bearer ${SUPERVISOR_TOKEN:-}" "${HA_API}/config" 2>/dev/null | jq -r '.time_zone // empty')
  if [ -n "$tz" ] && [ -e "/usr/share/zoneinfo/$tz" ]; then
    export TZ="$tz"
    log "Tijdzone: $tz"
  else
    log "Tijdzone niet opgehaald; gebruik ${TZ:-UTC}"
  fi
}

main() {
  mkdir -p "$DATA_DIR"
  set_timezone
  log "Ookla Speedtest app gestart. Tijden: $(opt '.schedule | join(", ")')"
  [ "$(opt '.accept_ookla_license')" = "true" ] || \
    log "LET OP: zet accept_ookla_license op true om de Ookla-licentie te accepteren en tests te laten draaien."
  publish
  [ "$(opt '.run_on_start')" = "true" ] && run_test

  listen_stdin &

  local last_run="" last_pub now_hm now_key
  last_pub=$(date +%s)
  while true; do
    now_hm=$(date +%H:%M)
    now_key=$(date +%Y%m%d%H%M)
    if [ "$now_key" != "$last_run" ] && opt '.schedule[]' | grep -qx "$now_hm"; then
      last_run="$now_key"
      run_test
    fi
    # Laatste resultaat regelmatig opnieuw publiceren, zodat de sensoren
    # na een herstart van Home Assistant direct weer een waarde hebben.
    if [ $(( $(date +%s) - last_pub )) -ge "$REPUBLISH_SECONDS" ]; then
      publish
      last_pub=$(date +%s)
    fi
    sleep 20
  done
}

if [ "${RUN_SH_SOURCE_ONLY:-}" != "1" ]; then
  main
fi
