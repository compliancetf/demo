#!/usr/bin/env bash
# Point the module sources in infra/*.tf at the compliance.tf ISO 27001 endpoint or back at
# the public Terraform Registry. Only source lines (and the version line of modules that use
# the HTTPS form) change. Idempotent. Uses perl so it behaves the same on macOS and Linux.
#
# Usage: scripts/swap-sources.sh to-upstream|to-iso [DIR]   (DIR defaults to infra/)
set -euo pipefail

mode="${1:-}"
dir="${2:-$(cd "$(dirname "$0")/.." && pwd)/infra}"

# Modules served in the HTTPS form with a recorded control exception (to-iso only).
# Format: module=control_id[,control_id]
ISO_EXCEPTIONS="alb=elb_application_classic_network_lb_prohibit_public_access"

case "$mode" in
  to-upstream | to-iso) ;;
  *)
    echo "usage: $0 to-upstream|to-iso [DIR]" >&2
    exit 2
    ;;
esac

shopt -s nullglob
files=("$dir"/*.tf)
if [ ${#files[@]} -eq 0 ]; then
  echo "no .tf files in $dir" >&2
  exit 1
fi

export ISO_EXCEPTIONS
for f in "${files[@]}"; do
  if [ "$mode" = "to-upstream" ]; then
    # HTTPS form: drop ?version and ?disable, restore the version argument
    # Registry form: drop the host
    perl -0777 -pi -e '
      s{^([ \t]*)source[ \t]*=[ \t]*"https://iso27001\.compliance\.tf/terraform-aws-modules/([\w-]+)/aws\?(?:[^"]*&)?version=([^&"]+)[^"]*"[ \t]*\n}{$1source  = "terraform-aws-modules/$2/aws"\n$1version = "$3"\n}mg;
      s{"iso27001\.compliance\.tf/(terraform-aws-modules/[\w-]+/aws)"}{"$1"}g;
    ' "$f"
  else
    perl -0777 -pi -e '
      my %exc = map { split /=/, $_, 2 } split /;/, $ENV{ISO_EXCEPTIONS};
      for my $m (keys %exc) {
        (my $ids = $exc{$m}) =~ s/,/&disable=/g;
        s{^([ \t]*)source[ \t]*=[ \t]*"terraform-aws-modules/\Q$m\E/aws"[ \t]*\n[ \t]*version[ \t]*=[ \t]*"([^"]+)"[ \t]*\n}{$1source = "https://iso27001.compliance.tf/terraform-aws-modules/$m/aws?version=$2&disable=$ids"\n}mg;
      }
      s{"(terraform-aws-modules/[\w-]+/aws)"}{"iso27001.compliance.tf/$1"}g;
    ' "$f"
  fi
done

echo "sources in $dir now point at: ${mode#to-}"
