# Dev instance runbook (kubectl, nautilus)

The Archify dev instance is `rtmon-archify-dev` (RTMon) + `rtmon-archify-sidecar`
in the `mfsada` namespace on NRP's nautilus cluster, alongside the existing
`rtmon-east-test`.

It polls sense-o-dev under `rtmon.instance-manager` and registers as the SENSE-O
deployment **`Real Time Mon - mfsada-archify`** (its own name — it does NOT own
`Real Time Mon`, which the live instance owns, so no UUID fight). Until a
reservation/task is assigned under that name it stays Ready and idle, which is
expected.

## Current resources

```
NAMESPACE  mfsada
  deploy/  rtmon-archify-dev       (RTMon, ghcr.io/groundsada/sense-rtmon:archify-dev)
           rtmon-archify-sidecar   (ghcr.io/groundsada/rtmon-archify:archify-dev)
  svc/     rtmon-archify-sidecar   (ClusterIP 8080)
  ingress/ rtmon-archify           (haproxy, mfsada-rtmon-archify.nrp-nautilus.io)
  pvc/     pvc-rtmon-archify-dev, pvc-rtmon-archify-sidecar
  secret/  rtmon-ghcr (pull), rtmon-archify-auth (token), rtmon-archify-config (rtmon.yaml + dev auth)
```

Wiring: RTMon → `http://rtmon-archify-sidecar:8080` (POST /v1/render, Bearer);
browser/demo → `https://mfsada-rtmon-archify.nrp-nautilus.io/diagrams/<uid>.html`
(or `/healthz`). Dashboards write to `mfsada-sense-grafana.nrp-nautilus.io`
in folder `Real Time Mon - mfsada-archify`. Grafana there must have
`GF_PANELS_DISABLE_SANITIZE_HTML=true` for the iframe to render.

## Bootstrap

```sh
cd deploy/k8s
bash setup-secrets.sh        # idempotent, regenerates Grafana key, reuses token
kubectl apply -f 01-pvc.yaml -f 02-sidecar.yaml -f 03-sidecar-svc.yaml \
              -f 04-rtmon.yaml -f 05-ingress.yaml
```

## Verify

```sh
kubectl -n mfsada get deploy rtmon-archify-dev rtmon-archify-sidecar   # both 1/1
kubectl -n mfsada exec deploy/rtmon-archify-sidecar -- wget -qO- http://127.0.0.1:8080/healthz
kubectl -n mfsada exec deploy/rtmon-archify-dev -- curl -s -m5 http://rtmon-archify-sidecar:8080/healthz
# expect: {"ok":true,"version":"2.17.0-dev.1"}
kubectl -n mfsada logs deploy/rtmon-archify-dev --tail=100 | grep -E "sweep|render|Archify|task|deployment"
```

## Assign a reservation (user step)

SENSE-O tasks carry `config.deployment`. To give this dev instance dashboard
work, create/point a task with `deployment: "Real Time Mon - mfsada-archify"` —
then RTMon picks it up on its 30s poll and the sidecar renders the Archify panel.

## Troubleshooting

- **`UUID does not match`**: two instances own the same deployment name. Verify
  rtmon.yaml `grafana_dev` is set (so folder is `Real Time Mon - mfsada-archify`,
  not bare `Real Time Mon`).
- **`Could not sweep Archify artifacts: unauthorized`**: sidecar token vs
  rtmon.yaml token mismatch. Regenerate/restart both after a secret change
  (setup-secrets.sh reuses the token; just restart the sidecar).
- **Readiness DEGRADED unreachable**: check `kubectl exec ... curl sense-o-dev...`;
  it's usually auth/registration, not network.
- **No Archify panel**: check Grafana `disable_sanitize_html`; without it the
  iframe is stripped. Dashboard warns otherwise.

## Teardown

```sh
kubectl -n mfsada delete deploy rtmon-archify-dev deploy/rtmon-archify-sidecar
kubectl -n mfsada delete svc rtmon-archify-sidecar ingress rtmon-archify
kubectl -n mfsada delete pvc pvc-rtmon-archify-dev pvc-rtmon-archify-sidecar
kubectl -n mfsada delete secret rtmon-archify-auth rtmon-archify-config rtmon-ghcr
```
