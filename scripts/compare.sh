#!/usr/bin/env bash
# Print a before/after table from two measurement files.
# Usage: scripts/compare.sh [before-label] [after-label]   (defaults: before after)
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
before_file="$project_dir/measurements/${1:-before}.txt"
after_file="$project_dir/measurements/${2:-after}.txt"
for measurement_file in "$before_file" "$after_file"; do
  [[ -f "$measurement_file" ]] || { echo "ERROR: missing $measurement_file" >&2; exit 1; }
done

awk -F= '
  # Metrics where a bigger number is better; everything else numeric is lower-is-better
  BEGIN { higher_is_better["mem_available_mb"]=1; higher_is_better["mem_free_mb"]=1 }
  FNR==NR { before[$1]=$2; order[++metric_count]=$1; next }
  { after[$1]=$2 }
  END {
    printf "%-40s %14s %14s %10s\n", "metric", "before", "after", "change"
    for (index_number=1; index_number<=metric_count; index_number++) {
      metric=order[index_number]
      if (metric=="label" || metric=="timestamp") continue
      before_value=before[metric]; after_value=(metric in after) ? after[metric] : "NA"
      change=""
      if (before_value ~ /^[0-9.]+$/ && after_value ~ /^[0-9.]+$/ && before_value+0 != 0) {
        percent=(after_value-before_value)/before_value*100
        better=(metric in higher_is_better) ? (percent>0) : (percent<0)
        change=sprintf("%+.0f%% %s", percent, (percent==0) ? "" : (better ? "better" : "worse"))
      }
      printf "%-40s %14s %14s %10s\n", metric, before_value, after_value, change
    }
  }' "$before_file" "$after_file"
