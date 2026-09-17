# K8s dev instance: RTMon + Archify sidecar (mfsada namespace)

A third, isolated RTMon instance on the NRP nautilus cluster, in your
`mfsada` namespace, side-by-side with `rtmon-east-test` (which it does not
touch). It polls **sense-o-dev** under the `rtmon.instance-manager` tag and
writes to the **dev Grafana** at `mfsada-sense-grafana.nrp-nautilus.io` under
the `mfsada-archify` Grafana dev folder, so it can't collide with anything on
the shared Grafana or with the east instances.

```
browser (demo) ── ingress https://mfsada-rtmon-archify.nrp-nautilus.io
                     ├── /diagrams/* ──> sidecar svc :8080 (GET only)
                     └── /healthz    ──> sidecar svc :8080
RTMon pod ──> http://rtmon-archify-sidecar:8080 (POST /v1/render, Bearer token)
```

## Files

| File | What |
|---|---|
| `01-pvc.yaml` | RTMon `/srv` volume |
| `02-sidecar.yaml` | sidecar Deployment (ghcr.io/groundsada/rtmon-archify:archify-dev) |
| `03-sidecar-svc.yaml` | ClusterIP service, port 8080 |
| `04-rtmon.yaml` | RTMon Deployment (ghcr.io/groundsada/sense-rtmon:archify-dev) |
| `05-ingress.yaml` | haproxy ingress, `/diagrams/` + `/healthz` only |
| `setup-secrets.sh` | creates all Secrets (no credentials in this repo) |
| `rtmon.yaml.tpl` | config template with `__ARCHIFY_TOKEN__`/`__GRAFANA_KEY__` |

## Setup

```sh
cd deploy/k8s
./setup-secrets.sh        # needs: kubectl (current ctx = nautilus), gh, curl
kubectl apply -f 01-pvc.yaml -f 02-sidecar.yaml -f 03-sidecar-svc.yaml \
              -f 04-rtmon.yaml -f 05-ingress.yaml
kubectl -n mfsada get deploy,pods -w
```

`setup-secrets.sh` does, without printing any value:

1. `rtmon-ghcr` – docker registry secret from `gh auth token` (private ghcr
   package pull; renew if the token rotates).
2. `rtmon-archify-auth` – a random `ARCHIFY_TOKEN`, generated here.
3. `rtmon-archify-config` – `rtmon-yaml` (rendered from `rtmon.yaml.tpl`) plus
   `sense-o-auth-dev.yaml` (dev SENSE-O credentials; sourced from the existing
   `opennsa` instance's `secret-rtmon` key, or from `./sense-o-auth-dev.yaml`
   if one is placed here).
4. Grafana API key for the dev Grafana and embeds it in `rtmon-yaml`.

## Verify

```sh
# sidecar is up and authenticates writes
kubectl -n mfsada exec deploy/rtmon-archify-sidecar -- wget -qO- http://127.0.0.1:8080/healthz
# RTMon is polling/rendering (watch for archify lines)
kubectl -n mfsada logs deploy/rtmon-archify-dev -f
# the panel URL once a dashboard exists:
#   https://mfsada-rtmon-archify.nrp-nautilus.io/diagrams/<uid>.html
```

## Tearing down

```sh
kubectl delete -n mfsada deploy/rtmon-archify-dev deploy/rtmon-archify-sidecar
kubectl delete -n mfsada svc/rtmon-archify-sidecar ingress/rtmon-archify pvc/pvc-rtmon-archify-dev
kubectl delete -n mfsada secret/rtmon-archify-auth secret/rtmon-archify-config secret/rtmon-ghcr
```

## Image notes

- RTMon image is **amd64** (`ghcr.io/groundsada/sense-rtmon:archify-dev`) –
  correct for this cluster; built from the `archify-sidecar` branch.
- Sidecar image is **multi-arch** (`archify-dev`).
- The dev-image workflows can only be dispatched once `dev-image.yaml` is on
  the default branch; until then rebuild with buildx locally (see README).
