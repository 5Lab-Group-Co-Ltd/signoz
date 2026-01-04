# SigNoz Agent Installer

One-liner installation for the SigNoz OpenTelemetry Collector agent.

## Install

```bash
curl -sSL https://raw.githubusercontent.com/5Lab-Group-Co-Ltd/signoz/master/install.sh | sudo bash
```

Or with a pre-configured endpoint:

```bash
curl -sSL https://raw.githubusercontent.com/5Lab-Group-Co-Ltd/signoz/master/install.sh | SIGNOZ_ENDPOINT="signoz.example.com:443" sudo -E bash
```

## Features

- **Auto-Architecture** – AMD64 / ARM64
- **Systemd Service** – Auto-enabled
- **Host Metrics** – CPU, memory, disk, network
- **Log Collection** – `/var/log/**/*.log`
- **PHP-FPM** – Optional status monitoring + OpenTelemetry tracing setup
- **MySQL/MariaDB** – Optional metrics

## Manage

```bash
sudo systemctl status signoz-otel-collector   # Status
sudo journalctl -u signoz-otel-collector -f   # Logs
sudo systemctl restart signoz-otel-collector  # Restart
```

## Uninstall

```bash
sudo systemctl disable --now signoz-otel-collector
sudo rm -rf /opt/signoz-otel-collector /etc/signoz-otel-collector
sudo rm /etc/systemd/system/signoz-otel-collector.service
sudo userdel signoz-otel-collector
sudo systemctl daemon-reload
```
