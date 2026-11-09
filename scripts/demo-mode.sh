#!/usr/bin/env bash
# Toggle the lines tagged demo:insecure / demo:secure in infra/*.tf. Idempotent; perl for macOS + Linux.
#   insecure: "# demo:insecure <line>"  -> "<line> # demo:insecure"
#             "<line> # demo:secure"    -> "# demo:secure <line>"
#   secure:   the reverse (the state on master)
#
# Usage: scripts/demo-mode.sh insecure|secure [DIR]   (DIR defaults to infra/)
set -euo pipefail

mode="${1:-}"
dir="${2:-$(cd "$(dirname "$0")/.." && pwd)/infra}"

case "$mode" in
  insecure) on=insecure off=secure ;;
  secure) on=secure off=insecure ;;
  *)
    echo "usage: $0 insecure|secure [DIR]" >&2
    exit 2
    ;;
esac

shopt -s nullglob
files=("$dir"/*.tf)
if [ ${#files[@]} -eq 0 ]; then
  echo "no .tf files in $dir" >&2
  exit 1
fi

export DEMO_ON="$on" DEMO_OFF="$off"
for f in "${files[@]}"; do
  perl -pi -e '
    my ($on, $off) = ($ENV{DEMO_ON}, $ENV{DEMO_OFF});
    s{^([ \t]*)# demo:\Q$on\E (.*?)[ \t]*$}{$1$2 # demo:$on};
    s{^([ \t]*)(?!#)(\S.*?)[ \t]*# demo:\Q$off\E[ \t]*$}{$1# demo:$off $2};
  ' "$f"
done

echo "demo lines in $dir now: $mode"
