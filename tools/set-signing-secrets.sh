#!/bin/zsh
# Sets the four signing and notary secrets once, on the xocialize-code organization, where every repo's release
# workflow reads them, then removes the per-repo copies from the gaea-plugin-* repos (a repo's own secret would
# override the organization's, and two copies drift when one is rotated).
# Values are read once, never echoed, and passed to gh on stdin (not argv).
#
#     tools/set-signing-secrets.sh <developer-id.p12>
#
# Needs the admin:org scope: gh auth refresh -h github.com -s admin:org
set -euo pipefail
ORG=xocialize-code
P12=${1:?usage: tools/set-signing-secrets.sh <developer-id.p12>}
[[ -f $P12 ]] || { echo "no such file: $P12" >&2; exit 1 }
gh auth status 2>&1 | grep -q "admin:org" || { echo "run first: gh auth refresh -h github.com -s admin:org" >&2; exit 1 }

read -rs "P12_PASSWORD?.p12 export password: "; echo
read -r  "APPLE_ID?Apple ID (team CFZS6RXUCP): "
read -rs "APP_PASSWORD?App-specific password: "; echo

# visibility all: the plugins are public repos, which the org's "private" visibility leaves out.
base64 -i "$P12"          | gh secret set DEVELOPER_ID_P12_BASE64   --org $ORG --visibility all
printf %s "$P12_PASSWORD" | gh secret set DEVELOPER_ID_P12_PASSWORD --org $ORG --visibility all
printf %s "$APPLE_ID"     | gh secret set NOTARY_APPLE_ID           --org $ORG --visibility all
printf %s "$APP_PASSWORD" | gh secret set NOTARY_APP_PASSWORD       --org $ORG --visibility all
gh secret list --org $ORG

for r in ${(f)"$(gh repo list $ORG --limit 200 --json name -q '.[].name' | grep '^gaea-plugin-' | sort)"}; do
  for s in ${(f)"$(gh secret list -R "$ORG/$r" --json name -q '.[].name')"}; do
    [[ $s == (DEVELOPER_ID_P12_BASE64|DEVELOPER_ID_P12_PASSWORD|NOTARY_APPLE_ID|NOTARY_APP_PASSWORD) ]] || continue
    gh secret delete "$s" -R "$ORG/$r"
  done
  echo "$r: uses the organization's secrets"
done
echo "Now delete $P12."
