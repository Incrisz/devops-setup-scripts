#!/usr/bin/env bash

# NODE EXPORTER INSTALLATION FOR UBUNTU x86_64 / amd64
# Run this after 01-prometheus.sh with: sudo bash 02-node-exporter.sh
# Node Exporter collects CPU, RAM, disk, network, and uptime metrics for dashboard 1860.

# Stop the installation if any command fails.
set -e

# Update Ubuntu's list of available packages.
apt-get update

# Install curl for downloading Node Exporter and tar for extracting it.
apt-get install -y curl tar

# Move into /tmp, a safe location for temporary installation files.
cd /tmp

# Download Node Exporter version 1.12.1 directly from the official release page.
curl -L -o node-exporter-1.12.1.tar.gz https://github.com/prometheus/node_exporter/releases/download/v1.12.1/node_exporter-1.12.1.linux-amd64.tar.gz

# Extract the downloaded Node Exporter archive.
tar -xzf node-exporter-1.12.1.tar.gz

# Create a protected Linux service account named node_exporter.
useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter || true

# Copy the Node Exporter program into a directory Linux uses for locally installed commands.
cp /tmp/node_exporter-1.12.1.linux-amd64/node_exporter /usr/local/bin/node_exporter

# Allow everyone to run Node Exporter while only root can replace it.
chmod 755 /usr/local/bin/node_exporter

# Create the systemd service file that tells Ubuntu how to run Node Exporter.
tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter --web.listen-address=127.0.0.1:9100 --collector.systemd --collector.processes
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Tell systemd to read the new Node Exporter service file.
systemctl daemon-reload

# Configure Node Exporter to start automatically whenever the server boots.
systemctl enable node_exporter

# Start Node Exporter now.
systemctl restart node_exporter

# Check that Node Exporter is returning server metrics locally on port 9100.
curl http://127.0.0.1:9100/metrics

# Check that the Prometheus configuration includes the Node Exporter target.
/usr/local/bin/promtool check config /etc/prometheus/prometheus.yml

# Restart Prometheus so it begins collecting Node Exporter metrics.
systemctl restart prometheus

# Display the Node Exporter service status.
systemctl status node_exporter --no-pager

# Remove the downloaded archive because it is no longer needed.
rm -f /tmp/node-exporter-1.12.1.tar.gz

# Remove the extracted temporary installation folder because it is no longer needed.
rm -rf /tmp/node_exporter-1.12.1.linux-amd64

# Confirm that Prometheus has started collecting the Node Exporter metrics.
echo "Node Exporter is ready. Import Grafana dashboard ID 1860 and select the Prometheus data source."

