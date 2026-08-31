# Server Monitoring Setup

Run the installation files in this order:

```bash
sudo bash 01-prometheus.sh
sudo bash 02-node-exporter.sh
sudo bash 03-grafana.sh
```

```text
Your server resources
 CPU | RAM | Disk | Network
            |
            v
 Node Exporter (collects metrics)
            |
            v
 Prometheus (collects and stores metrics)
            |
            v
 Grafana (shows dashboards in your browser)
```

| File | Function |
| --- | --- |
| `01-prometheus.sh` | Installs Prometheus. It collects and stores monitoring data. |
| `02-node-exporter.sh` | Installs Node Exporter. It reads the server's CPU, memory, disk, network, and uptime data. |
| `03-grafana.sh` | Installs Grafana. It turns Prometheus data into charts and dashboards. |

Open Grafana at `http://YOUR_SERVER_IP:3000`, then import dashboard ID `1860` and select the **Prometheus** data source.

