#!/usr/bin/env bash
# Assert that switching to compliance.tf modules changes resources in place only:
# 0 to create, 0 to delete (a replace counts as both). Prints the attributes that flip.
#
# Usage: scripts/check-plan.sh PLAN.json   (from: terraform show -json tfplan > PLAN.json)
set -euo pipefail

plan="${1:?usage: $0 PLAN.json}"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
[ -s "$plan" ] || { echo "plan file $plan is missing or empty" >&2; exit 2; }

creates=$(jq '[.resource_changes[]? | select(.change.actions | index("create"))] | length' "$plan")
deletes=$(jq '[.resource_changes[]? | select(.change.actions | index("delete"))] | length' "$plan")
updates=$(jq '[.resource_changes[]? | select(.change.actions == ["update"])] | length' "$plan")

echo "Plan: ${creates} to create, ${updates} to update in place, ${deletes} to delete"
echo
echo "Attributes that flip:"
jq -r '
  [
    ["enable_key_rotation"],
    ["kms_master_key_id"],
    ["map_public_ip_on_launch"],
    ["network_configuration", 0, "assign_public_ip"],
    ["retention_in_days"],
    ["kms_key_id"],
    ["metadata_options", 0, "http_tokens"]
  ] as $paths
  | .resource_changes[]?
  | select(.change.actions == ["update"])
  | .address as $addr
  | .change as $c
  | $paths[] as $p
  | ($c.before | try getpath($p) catch null) as $old
  | ($c.after | try getpath($p) catch null) as $new
  | (($c.after_unknown // {}) | try getpath($p) catch null) as $unknown
  | select($unknown == true or $old != $new)
  | "  \($addr): \($p | map(tostring) | join(".")) \($old | tojson) -> \(if $unknown == true then "(known after apply)" else ($new | tojson) end)"
' "$plan" | sort

if [ "$creates" -ne 0 ] || [ "$deletes" -ne 0 ]; then
  echo
  echo "FAIL: expected 0 create and 0 delete. Resources that would be created or destroyed:" >&2
  jq -r '.resource_changes[]? | select(.change.actions | (index("create") or index("delete"))) | "  \(.address): \(.change.actions | join(","))"' "$plan" >&2
  exit 1
fi

echo
echo "OK: in-place changes only"
