# AGENTS.md - SigNoz Agent Provisioner

This repository contains the **Enterprise SigNoz Agent Provisioner**, a self-contained shell script for installing and configuring the SigNoz OpenTelemetry Collector on Linux servers.

---

## Project Overview

| Component | Description |
|-----------|-------------|
| `install.sh` | Main provisioner script that downloads, configures, and installs the SigNoz OTel collector as a systemd service |

### Features

- Auto-detects OS architecture (AMD64/ARM64)
- Creates systemd service automatically
- Supports MySQL/MariaDB monitoring
- Supports PHP-FPM monitoring
- Configures host metrics, logs, and traces pipelines

---

## Security Guidelines

> [!CAUTION]
> **Never commit secrets to this repository.**

### Sensitive Data Handling

The following are considered **secrets** and must NEVER be hardcoded:

| Secret Type | Safe Handling |
|-------------|---------------|
| `SIGNOZ_ENDPOINT` | Prompt user at runtime or use environment variable |
| MySQL credentials | Prompt user at runtime (already implemented) |
| PHP-FPM URLs | Prompt user at runtime (already implemented) |
| API keys/tokens | Use environment variables only |
| TLS certificates | Reference file paths, never embed content |

### Current Security Measures

- Credentials are prompted interactively at runtime
- Passwords use `read -s` for hidden input
- No credentials are stored in the script

---

## Development Guidelines

### Code Style

- Use meaningful function names (e.g., `log_info`, `log_err`, `add_module`)
- Include phase comments for major script sections
- Use color-coded logging for user feedback

### Testing Changes

```bash
# Syntax check
bash -n install.sh

# Dry run on test VM (never run on production without testing)
sudo ./install.sh
```

### Adding New Workload Detectors

When adding support for new services (e.g., Redis, Nginx):

1. Add process detection using `pgrep`
2. Prompt user for enable/disable
3. Collect required configuration interactively
4. Use `add_module` function to register the receiver
5. Follow existing MySQL/PHP-FPM patterns

---

## File Structure

```
signoz/
├── AGENTS.md      # This file - AI agent guidelines
└── install.sh     # Main provisioner script
```

---

## Installation Paths

| Path | Purpose |
|------|---------|
| `/opt/signoz-otel-collector` | Binary installation directory |
| `/etc/signoz-otel-collector` | Configuration directory |
| `/etc/systemd/system/signoz-otel-collector.service` | Systemd service file |

---

## Common Tasks

### Viewing Logs

```bash
journalctl -u signoz-otel-collector -f
```

### Restarting Service

```bash
sudo systemctl restart signoz-otel-collector
```

### Modifying Configuration

```bash
sudo nano /etc/signoz-otel-collector/config.yaml
sudo systemctl restart signoz-otel-collector
```
