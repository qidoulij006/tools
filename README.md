# tools

## Codex Web Terminal

This repository includes a one-click installer for running Codex as a persistent web terminal on a remote Linux server.

Script:
- `install-codex-web.sh`

### What it does

The installer sets up:
- `ttyd` for browser-based terminal access
- `tmux` for persistent sessions
- `systemd` service `codex-web.service`
- optional firewall opening for the web terminal port

The session stays alive after browser disconnects, and reconnecting attaches back to the same Codex session.

### Quick install

```bash
wget https://raw.githubusercontent.com/qidoulij006/tools/main/install-codex-web.sh -O install-codex-web.sh
chmod +x install-codex-web.sh
sudo bash install-codex-web.sh --password '你的强密码'
```

### Custom install example

```bash
sudo bash install-codex-web.sh \
  --username codex \
  --password '你的强密码' \
  --port 7681
```

### Access after installation

Open in browser:

```text
http://你的服务器IP:7681
```

Login credentials:
- Username: the value passed to `--username` or default `codex`
- Password: the value passed to `--password`

### Optional parameters

- `--username <name>`: web login username
- `--password <password>`: web login password
- `--port <port>`: ttyd port, default `7681`
- `--workdir <path>`: Codex working directory
- `--codex-bin <path>`: Codex binary path
- `--session-name <name>`: tmux session name
- `--install-dir <path>`: script install directory

### Verify service

```bash
systemctl status codex-web.service
curl -I http://127.0.0.1:7681
```

### How it works

Implementation chain:

```text
systemd -> ttyd -> start-codex-tmux.sh -> tmux -> codex
```

- `ttyd` exposes the terminal in the browser
- `tmux` keeps the Codex session persistent
- `systemd` keeps the service running after reboots

### Notes

- Install `codex` first before running this script
- For public internet exposure, it is better to place this behind Nginx and HTTPS
- Default port is `7681`; change it if needed
