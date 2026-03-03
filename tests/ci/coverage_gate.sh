#!/usr/bin/env bash
# tests/ci/coverage_gate.sh - Enforce minimum coverage threshold from Cobertura XML

set -euo pipefail

XML_FILE=""
MIN_PERCENT="80"
METRICS_FILE=""

usage() {
  cat <<USAGE
Usage: coverage_gate.sh --xml <cobertura.xml> [--min-percent 80] [--metrics-file /tmp/coverage.env]
USAGE
}

write_metrics() {
  local status="$1"
  local line_rate="$2"
  local percent="$3"
  local reason="$4"

  [[ -n "$METRICS_FILE" ]] || return 0
  cat >"$METRICS_FILE" <<EOF_METRICS
COVERAGE_GATE_STATUS=${status}
COVERAGE_LINE_RATE=${line_rate}
COVERAGE_PERCENT=${percent}
COVERAGE_THRESHOLD=${MIN_PERCENT}
COVERAGE_REASON=${reason}
EOF_METRICS
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --xml)
      XML_FILE="$2"
      shift 2
      ;;
    --min-percent)
      MIN_PERCENT="$2"
      shift 2
      ;;
    --metrics-file)
      METRICS_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$XML_FILE" ]]; then
  echo "Error: --xml is required" >&2
  usage >&2
  exit 1
fi

if [[ ! -f "$XML_FILE" ]]; then
  write_metrics "error" "" "" "missing_xml"
  echo "Error: coverage xml not found: $XML_FILE" >&2
  exit 1
fi

if ! awk -v v="$MIN_PERCENT" 'BEGIN{exit (v ~ /^[0-9]+([.][0-9]+)?$/ ? 0 : 1)}'; then
  write_metrics "error" "" "" "invalid_threshold"
  echo "Error: invalid --min-percent: $MIN_PERCENT" >&2
  exit 1
fi

line_rate="$(awk 'match($0, /line-rate="[0-9.]+"/) { value=substr($0, RSTART+11, RLENGTH-12); print value; exit }' "$XML_FILE")"

if [[ -z "$line_rate" ]]; then
  write_metrics "error" "" "" "missing_line_rate"
  echo "Error: line-rate not found in $XML_FILE" >&2
  exit 1
fi

if ! awk -v v="$line_rate" 'BEGIN{exit (v ~ /^[0-9]+([.][0-9]+)?$/ ? 0 : 1)}'; then
  write_metrics "error" "$line_rate" "" "invalid_line_rate"
  echo "Error: invalid line-rate in $XML_FILE: $line_rate" >&2
  exit 1
fi

coverage_percent="$(awk -v rate="$line_rate" 'BEGIN{printf "%.2f", rate * 100}')"

if awk -v c="$coverage_percent" -v m="$MIN_PERCENT" 'BEGIN{exit !(c + 0 >= m + 0)}'; then
  write_metrics "pass" "$line_rate" "$coverage_percent" "threshold_met"
  echo "Coverage gate passed: ${coverage_percent}% >= ${MIN_PERCENT}%"
  exit 0
fi

write_metrics "fail" "$line_rate" "$coverage_percent" "below_threshold"
echo "Coverage gate failed: ${coverage_percent}% < ${MIN_PERCENT}%" >&2
exit 1
