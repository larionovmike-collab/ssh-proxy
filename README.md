# ssh-proxy

Lightweight SOCKS5 proxy over SSH tunnel written in Go.

`ssh-proxy` allows you to quickly create a local SOCKS5 proxy that routes all traffic through a remote SSH server.

---

## 🚀 Features

- SOCKS5 proxy over SSH tunnel
- Password authentication (SSH)
- Lightweight and fast (single binary)
- No external dependencies at runtime
- Works on Linux (Ubuntu recommended)

---

## 📦 Requirements

- Linux (Ubuntu 20.04+ recommended)
- SSH server access
- Optional: Go (only if building from source)

---

## ⚙️ Installation

### One-line install (recommended)

```bash
bash <(curl -sSL https://raw.githubusercontent.com/larionovmike-collab/ssh-proxy/refs/heads/main/install.sh)
