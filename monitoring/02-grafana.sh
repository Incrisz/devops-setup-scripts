#!/usr/bin/env bash

# GRAFANA INSTALLATION FOR UBUNTU
# Install Prometheus with 01-prometheus.sh before running this file.
# Run this complete file with: sudo bash 02-grafana.sh
# Grafana will be available at: http://YOUR_SERVER_IP:3000

# Stop the installation if any command fails.
set -e

# Update Ubuntu's list of available packages.
apt-get update

# Install the tools needed to add Grafana's official package repository.
apt-get install -y ca-certificates curl gnupg

# Create the standard folder used to store trusted package-signing keys.
mkdir -p /etc/apt/keyrings

# Download Grafana's official package-signing key.
curl -L -o /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key

# Make the signing key readable by Ubuntu's package manager.
chmod 644 /etc/apt/keyrings/grafana.asc

# Add Grafana's official stable software repository to Ubuntu.
echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list

# Update the package list again so Ubuntu can find Grafana in the new repository.
apt-get update

# Install the open-source edition of Grafana.
apt-get install -y grafana

# Create the folder used for automatically configured Grafana data sources.
mkdir -p /etc/grafana/provisioning/datasources

# Create a Grafana data source that connects to the Prometheus service installed first.
tee /etc/grafana/provisioning/datasources/prometheus.yml > /dev/null <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
    editable: true
EOF

# Give root ownership while allowing the grafana service to read the data-source file.
chown root:grafana /etc/grafana/provisioning/datasources/prometheus.yml

# Protect the data-source file from other users on the server.
chmod 640 /etc/grafana/provisioning/datasources/prometheus.yml

# Configure Grafana to start automatically whenever the server boots.
systemctl enable grafana-server

# Start Grafana now and load the Prometheus data source.
systemctl restart grafana-server

# Give Grafana a few seconds to finish its first startup.
sleep 10

# Display the Grafana service status.
systemctl status grafana-server --no-pager

# Check that Grafana's database and web service are healthy.
curl http://127.0.0.1:3000/api/health

# Print the address and first-login details for the learner.
echo "Open Grafana at http://YOUR_SERVER_IP:3000"

# Remind the learner to replace the default password immediately.
echo "First login: admin / admin - change this password when Grafana asks."

