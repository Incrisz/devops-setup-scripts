#!/usr/bin/env bash

# PROMETHEUS INSTALLATION FOR UBUNTU x86_64 / amd64
# Run this complete file with: sudo bash 01-prometheus.sh
# Prometheus will be available at: http://YOUR_SERVER_IP:9090

# Stop the installation if any command fails.
set -e

# Update Ubuntu's list of available packages.
apt-get update

# Install curl for downloading files and tar for extracting them.
apt-get install -y curl tar

# Move into /tmp, a safe location for temporary installation files.
cd /tmp

# Download Prometheus version 3.14.0 directly from the official release page.
curl -L -o prometheus-3.14.0.tar.gz https://github.com/prometheus/prometheus/releases/download/v3.14.0/prometheus-3.14.0.linux-amd64.tar.gz

# Extract the downloaded Prometheus archive.
tar -xzf prometheus-3.14.0.tar.gz

# Create a protected Linux service account named prometheus.
useradd --system --no-create-home --shell /usr/sbin/nologin prometheus || true

# Copy the Prometheus program into a directory Linux uses for locally installed commands.
cp /tmp/prometheus-3.14.0.linux-amd64/prometheus /usr/local/bin/prometheus

# Copy promtool, the command used to check Prometheus configuration files.
cp /tmp/prometheus-3.14.0.linux-amd64/promtool /usr/local/bin/promtool

# Allow everyone to run the two programs while only root can replace them.
chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool

# Create the folder that will contain the Prometheus configuration.
mkdir -p /etc/prometheus

# Create the folder in which Prometheus will save its monitoring data.
mkdir -p /var/lib/prometheus

# Give the prometheus account ownership of its data folder.
chown prometheus:prometheus /var/lib/prometheus

# Create the main Prometheus configuration file.
tee /etc/prometheus/prometheus.yml > /dev/null <<'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node"
    static_configs:
      - targets: ["localhost:9100"]
EOF

# Allow root to edit the configuration and allow the prometheus service to read it.
chown root:prometheus /etc/prometheus/prometheus.yml

# Protect the configuration from other users on the server.
chmod 640 /etc/prometheus/prometheus.yml

# Check the configuration for typing or formatting errors.
/usr/local/bin/promtool check config /etc/prometheus/prometheus.yml

# Create the systemd service file that tells Ubuntu how to run Prometheus.
tee /etc/systemd/system/prometheus.service > /dev/null <<'EOF'
[Unit]
Description=Prometheus Monitoring System
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --storage.tsdb.retention.time=15d --web.listen-address=0.0.0.0:9090
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Tell systemd to read the new Prometheus service file.
systemctl daemon-reload

# Configure Prometheus to start automatically whenever the server boots.
systemctl enable prometheus

# Start Prometheus now.
systemctl restart prometheus

# Display the service status; press q if the output opens in a pager.
systemctl status prometheus --no-pager

# Check that the local Prometheus web service is ready.
curl http://127.0.0.1:9090/-/ready

# Remove the downloaded archive because it is no longer needed.
rm -f /tmp/prometheus-3.14.0.tar.gz

# Remove the extracted temporary installation folder because it is no longer needed.
rm -rf /tmp/prometheus-3.14.0.linux-amd64

# Print the address the learner should open in a web browser.
echo "Open Prometheus at http://YOUR_SERVER_IP:9090"
