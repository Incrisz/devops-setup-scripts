#!/usr/bin/env bash

# Exit immediately if a command fails, an unset variable is used, or a pipeline fails.
set -euo pipefail

# This guide installs native Prometheus and Grafana services on Ubuntu x86_64.
# Run the whole file with: sudo bash process.sh
# You can also copy and run each explained command one at a time as root.

# Store the Prometheus version in one place so it is easy to update later.
PROMETHEUS_VERSION="3.14.0"

# Store the official SHA-256 checksum so a damaged or altered download is rejected.
PROMETHEUS_SHA256="f665c6da19eb7ba399c915d30c7d9793c9b417bf8a749b504bc470678631478d"

# Stop with a helpful message unless this script is being run as root (sudo is fine).
if [[ "${EUID}" -ne 0 ]]; then
  # Print the exact command the learner should use.
  echo "Please run this script with: sudo bash process.sh"
  # Exit because package and system-service installation requires administrator access.
  exit 1
fi

# Stop if the server is not x86_64 because this guide downloads the amd64 binary.
if [[ "$(uname -m)" != "x86_64" ]]; then
  # Explain why the installer cannot safely continue on this CPU architecture.
  echo "This guide currently supports x86_64/amd64 servers only."
  # Exit before downloading an incompatible program.
  exit 1
fi

# Refresh Ubuntu's package list before installing software.
apt-get update

# Install tools used to securely download, verify, and unpack the software.
apt-get install -y ca-certificates curl gnupg tar

# Create a temporary working folder that is automatically unique.
INSTALL_TMP="$(mktemp -d)"

# Delete the temporary working folder whenever the script exits.
trap 'rm -rf "${INSTALL_TMP}"' EXIT

# Download the official Prometheus release archive from GitHub.
curl --fail --location --show-error --output "${INSTALL_TMP}/prometheus.tar.gz" "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

# Verify the archive checksum before installing anything from it.
echo "${PROMETHEUS_SHA256}  ${INSTALL_TMP}/prometheus.tar.gz" | sha256sum --check -

# Unpack the verified Prometheus archive into the temporary folder.
tar --extract --gzip --file "${INSTALL_TMP}/prometheus.tar.gz" --directory "${INSTALL_TMP}"

# Create a locked system account for Prometheus if it does not already exist.
id prometheus >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin prometheus

# Create the Prometheus configuration directory with safe permissions.
install --directory --owner=root --group=prometheus --mode=0750 /etc/prometheus

# Create the Prometheus data directory and give the service account ownership.
install --directory --owner=prometheus --group=prometheus --mode=0750 /var/lib/prometheus

# Install the Prometheus server program into the standard local binary directory.
install --owner=root --group=root --mode=0755 "${INSTALL_TMP}/prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /usr/local/bin/prometheus

# Install promtool, which checks Prometheus configuration and rules.
install --owner=root --group=root --mode=0755 "${INSTALL_TMP}/prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" /usr/local/bin/promtool

# Write a basic configuration that makes Prometheus monitor its own health and metrics.
install --owner=root --group=prometheus --mode=0640 /dev/stdin /etc/prometheus/prometheus.yml <<'PROMETHEUS_CONFIG'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - localhost:9090
PROMETHEUS_CONFIG

# Validate the Prometheus configuration before starting the service.
/usr/local/bin/promtool check config /etc/prometheus/prometheus.yml

# Create a systemd unit so Prometheus runs in the background and starts after reboot.
install --owner=root --group=root --mode=0644 /dev/stdin /etc/systemd/system/prometheus.service <<'PROMETHEUS_SERVICE'
[Unit]
Description=Prometheus Monitoring System
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --storage.tsdb.retention.time=15d --web.listen-address=0.0.0.0:9090
Restart=on-failure
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/prometheus

[Install]
WantedBy=multi-user.target
PROMETHEUS_SERVICE

# Create the standard directory in which modern APT repository keys are stored.
install --directory --owner=root --group=root --mode=0755 /etc/apt/keyrings

# Download Grafana's official signing key over HTTPS.
curl --fail --location --show-error --output /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key

# Make the signing key readable by APT while keeping it writable only by root.
chmod 0644 /etc/apt/keyrings/grafana.asc

# Add Grafana's stable official APT repository without duplicating the entry.
echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list

# Refresh package information so Ubuntu can see packages in the Grafana repository.
apt-get update

# Install the open-source Grafana package without asking interactive questions.
DEBIAN_FRONTEND=noninteractive apt-get install -y grafana

# Create Grafana's data-source provisioning directory if it does not exist.
install --directory --owner=root --group=grafana --mode=0750 /etc/grafana/provisioning/datasources

# Provision the local Prometheus service as Grafana's default data source.
install --owner=root --group=grafana --mode=0640 /dev/stdin /etc/grafana/provisioning/datasources/prometheus.yml <<'GRAFANA_DATASOURCE'
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
    editable: true
GRAFANA_DATASOURCE

# Tell systemd to reload unit definitions after creating the Prometheus unit.
systemctl daemon-reload

# Enable Prometheus at boot and start or restart it now to load this configuration.
systemctl enable --now prometheus

# Restart Prometheus when this script is run again after an upgrade or config change.
systemctl restart prometheus

# Enable Grafana at boot and start it now.
systemctl enable --now grafana-server

# Restart Grafana so it reads the provisioned Prometheus data source.
systemctl restart grafana-server

# If Ubuntu's UFW firewall is active, allow browsers to reach Prometheus on TCP 9090.
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
  # Add the Prometheus port to the active firewall rules.
  ufw allow 9090/tcp comment 'Prometheus web interface'
  # Add the Grafana port to the active firewall rules.
  ufw allow 3000/tcp comment 'Grafana web interface'
fi

# Ask Prometheus's local health endpoint to confirm that the server is ready.
curl --fail --silent --show-error --retry 10 --retry-all-errors --retry-delay 2 http://127.0.0.1:9090/-/ready

# Ask Grafana's local health endpoint to confirm that the server is responding.
curl --fail --silent --show-error --retry 30 --retry-all-errors --retry-delay 2 http://127.0.0.1:3000/api/health

# Show the installed Prometheus version for the installation record.
/usr/local/bin/prometheus --version

# Show the installed Grafana version for the installation record.
/usr/sbin/grafana-server --version

# Print the URLs and initial Grafana credentials for the learner.
echo "Prometheus: http://SERVER_IP:9090"

# Remind the learner that Grafana uses port 3000.
echo "Grafana:    http://SERVER_IP:3000"

# Explain Grafana's first-login credentials and required password change.
echo "First Grafana login: admin / admin (Grafana will ask you to change it)."

# Warn that a cloud firewall or security group may also need these two TCP ports opened.
echo "If this is a cloud server, allow inbound TCP 3000 and 9090 only from trusted IP addresses."
