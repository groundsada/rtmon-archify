# RTMon dev-instance config (rendered by setup-secrets.sh, not committed).
# Values in __UPPER__ are substituted. All credentials stay in Secrets.
#
# grafana_dev names this instance's own deployment in SENSE-O:
# "Real Time Mon - mfsada-archify". Only one RTMon instance may own a
# deployment name (the UUID ownership check), so a dev instance must NOT use
# the bare "Real Time Mon" that the live instance owns. Once SENSE-O assigns
# tasks under this deployment name, this instance picks them up and keeps its
# dashboards in its own folder. Until then it registers, is Ready, and finds
# no tasks - which is the expected idle state.
sleep_timer: 30
workdir: /srv/
grafana_host: https://mfsada-sense-grafana.nrp-nautilus.io
grafana_api_key: __GRAFANA_API_KEY__
grafana_username: admin
grafana_password: admin
grafana_folder: Real Time Mon
grafana_dev: mfsada-archify

template_path: /etc/rtmon/templates
template_tag: V0.5
rerender_per_cycle: 5

senseo_assignee: "rtmon.instance-manager"
sense_timeout: 30

sense_endpoints:
  sense-o-dev.es.net: /etc/sense-o-auth.yaml

override_url: https://raw.githubusercontent.com/esnet/sense-rtmon/master/autogole-api/packaging/files/etc/overrides.yaml

hostcert: /etc/grid-security/hostcert.pem
hostkey: /etc/grid-security/hostkey.pem

# The Archify topology diagram, served by the sidecar on this pod.
topdiagrams: Both
archify:
  sidecar_url: http://rtmon-archify-sidecar:8080
  token: __ARCHIFY_TOKEN__
  diagram_url_base: https://mfsada-rtmon-archify.nrp-nautilus.io
  quality: standard
  max_fix_rounds: 3
  render_timeout: 60

prometheus_url: https://autogole-prometheus.nrp-nautilus.io
prometheus_username: __PROM_USER__
prometheus_password: __PROM_PASS__
