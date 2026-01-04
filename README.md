# SigNoz Agent Installer

One-liner installation for the SigNoz OpenTelemetry Collector agent.

## Install

### Interactive Mode (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/5Lab-Group-Co-Ltd/signoz/master/install.sh -o install.sh
sudo bash install.sh
```

### Non-Interactive Mode

```bash
curl -sSL https://raw.githubusercontent.com/5Lab-Group-Co-Ltd/signoz/master/install.sh -o /tmp/signoz-install.sh
sudo SIGNOZ_ENDPOINT="signoz.example.com:443" bash /tmp/signoz-install.sh
```

### With MySQL Monitoring

```bash
sudo SIGNOZ_ENDPOINT="signoz.example.com:443" \
     ENABLE_MYSQL=y \
     MYSQL_USER="monitor" \
     MYSQL_PASS="secret" \
     bash /tmp/signoz-install.sh
```

### With PHP-FPM Monitoring

```bash
sudo SIGNOZ_ENDPOINT="signoz.example.com:443" \
     ENABLE_PHPFPM=y \
     bash /tmp/signoz-install.sh
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SIGNOZ_ENDPOINT` | Yes | SigNoz endpoint (e.g., `signoz.5lab.co:443`) |
| `ENABLE_MYSQL` | No | Set to `y` to enable MySQL monitoring |
| `MYSQL_USER` | If MySQL | MySQL username |
| `MYSQL_PASS` | If MySQL | MySQL password |
| `MYSQL_HOST` | No | MySQL host (default: `127.0.0.1:3306`) |
| `ENABLE_PHPFPM` | No | Set to `y` to enable PHP-FPM monitoring |
| `ENABLE_PHP_OTEL` | No | Set to `y` to install PHP OpenTelemetry extensions |

## Features

- **Auto-Architecture** – AMD64 / ARM64
- **Systemd Service** – Auto-enabled
- **Host Metrics** – CPU, memory, disk, network, paging
- **Log Collection** – `/var/log/**/*.log`
- **PHP-FPM** – Status monitoring + OpenTelemetry tracing setup
- **MySQL/MariaDB** – Optional connection metrics

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
