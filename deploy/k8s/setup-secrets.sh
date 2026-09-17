#!/usr/bin/env bash
# Create the Secrets for the RTMon Archify dev instance in the mfsada
# namespace on nautilus. No secret value is ever printed.
#
# Sources (all read from the cluster, never committed):
#   - SENSE-O dev credentials: opennsa/secret-rtmon key sense-o-auth-yaml
#     (API_ENDPOINT sense-o-dev.es.net:8443). Override with ./sense-o-auth-dev.yaml.
#   - Prometheus creds: mfsada/secret-rtmon rtmon-yaml (existing instance).
#   - Grafana API key: minted from the dev Grafana (admin:admin).
#   - ghcr pull secret: gh auth token (private sense-rtmon ghcr package).
#   - ARCHIFY_TOKEN: generated here.
set -euo pipefail

NS=${NS:-mfsada}

if ! kubectl config current-context | grep -q nautilus; then
  echo "kubectl context is not nautilus; refusing." >&2
  exit 1
fi

# 1. ghcr pull secret for the private sense-rtmon package.
echo "== rtmon-ghcr =="
kubectl -n "$NS" create secret docker-registry rtmon-ghcr \
  --docker-server=ghcr.io --docker-username=groundsada \
  --docker-password="$(gh auth token)" \
  --dry-run=client -o yaml | kubectl -n "$NS" apply -f - >/dev/null
echo "  ok"

# 2. ARCHIFY_TOKEN - reused if present (so the running sidecar keeps working),
# generated once otherwise; never printed; must match rtmon.yaml.
echo "== rtmon-archify-auth =="
EXISTING=$(kubectl -n "$NS" get secret rtmon-archify-auth -o jsonpath='{.data.archify-token}' 2>/dev/null | base64 -d 2>/dev/null || true)
if [[ -n "$EXISTING" ]]; then
  TOKEN="$EXISTING"
  echo "  ok (reused)"
else
  TOKEN=$(openssl rand -hex 24)
  kubectl -n "$NS" create secret generic rtmon-archify-auth \
    --from-literal=archify-token="$TOKEN" \
    --dry-run=client -o yaml | kubectl -n "$NS" apply -f - >/dev/null
  echo "  ok (generated)"
fi

# 3. SENSE-O dev credentials.
echo "== sense-o-auth-dev =="
if [[ -f sense-o-auth-dev.yaml ]]; then
  cp sense-o-auth-dev.yaml /tmp/sense-o-auth-dev.yaml
else
  kubectl -n opennsa get secret secret-rtmon \
    -o jsonpath='{.data.sense-o-auth-yaml}' | base64 -d > /tmp/sense-o-auth-dev.yaml
fi
# verify it is actually the dev endpoint before we wire it in
grep -q "sense-o-dev.es.net" /tmp/sense-o-auth-dev.yaml || { echo "warning: not sense-o-dev endpoint"; }
echo "  ok"

# 4. Grafana API key (minted live; idempotent - deletes an old one first).
echo "== grafana api key =="
KEY_ID=$(curl -s -u admin:admin https://mfsada-sense-grafana.nrp-nautilus.io/api/auth/keys | \
  python3 -c "import sys,json; ks=json.load(sys.stdin); print(next((k['id'] for k in ks if k['name']=='rtmon-archify-dev'), ''))" 2>/dev/null || true)
if [[ -n "$KEY_ID" ]]; then
  curl -s -u admin:admin -X DELETE "https://mfsada-sense-grafana.nrp-nautilus.io/api/auth/keys/$KEY_ID" >/dev/null
fi
GRAFANA_KEY=$(curl -s -u admin:admin -H "Content-Type: application/json" \
  -d '{"name":"rtmon-archify-dev","role":"Admin","secondsToLive":0}' \
  https://mfsada-sense-grafana.nrp-nautilus.io/api/auth/keys | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['key'])")
echo "  ok"

# 5. Prometheus user/pass from the existing mfsada instance.
promuser() { kubectl -n "$NS" get secret secret-rtmon -o jsonpath='{.data.rtmon-yaml}' 2>/dev/null | base64 -d | grep '^prometheus_username:' | awk '{print $2}' | tr -d '"'; }
prompass() { kubectl -n "$NS" get secret secret-rtmon -o jsonpath='{.data.rtmon-yaml}' 2>/dev/null | base64 -d | grep '^prometheus_password:' | awk '{print $2}' | tr -d '"'; }

# 6. Render rtmon.yaml (simple sed: placeholders are fixed-width).
echo "== rtmon.yaml =="
sed -e "s|__GRAFANA_API_KEY__|$GRAFANA_KEY|" \
    -e "s|__ARCHIFY_TOKEN__|$TOKEN|" \
    -e "s|__PROM_USER__|$(promuser)|" \
    -e "s|__PROM_PASS__|$(prompass)|" \
    rtmon.yaml.tpl > /tmp/rtmon-rendered.yaml
grep -q "ARCHIFY_TOKEN__" /tmp/rtmon-rendered.yaml && { echo "unsubstituted placeholder!"; exit 1; }

# 7. Merge into the config secret (dev auth + rtmon.yaml).
echo "== rtmon-archify-config =="
kubectl -n "$NS" create secret generic rtmon-archify-config \
  --from-file=sense-o-auth-dev-yaml=/tmp/sense-o-auth-dev.yaml \
  --from-file=rtmon-yaml=/tmp/rtmon-rendered.yaml \
  --dry-run=client -o yaml | kubectl -n "$NS" apply -f - >/dev/null
rm -f /tmp/sense-o-auth-dev.yaml /tmp/rtmon-rendered.yaml
echo "  ok"

echo
echo "Done. Apply:"
echo "  kubectl apply -f 01-pvc.yaml -f 02-sidecar.yaml -f 03-sidecar-svc.yaml -f 04-rtmon.yaml -f 05-ingress.yaml"
echo "If the Deployment exists: kubectl -n $NS rollout restart deploy/rtmon-archify-dev"
