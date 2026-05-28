#!/usr/bin/env bash

set -e

BINARY_NAME="ssh-proxy"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"
REPO_URL="https://github.com/larionovmike-collab/ssh-proxy.git"
TMP_DIR="/tmp/ssh-proxy-install"
SERVICE_NAME="ssh-proxy"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

print_info() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

uninstall() {
    print_info "Stopping and removing systemd service..."

    if systemctl list-units --full -all | grep -q "${SERVICE_NAME}.service"; then
        sudo systemctl stop "$SERVICE_NAME" || true
        sudo systemctl disable "$SERVICE_NAME" || true
    fi

    if [ -f "$SERVICE_PATH" ]; then
        sudo rm -f "$SERVICE_PATH"
        print_info "Removed service file: $SERVICE_PATH"
    fi

    sudo systemctl daemon-reload || true

    print_info "Removing binary..."

    if [ -f "$INSTALL_PATH" ]; then
        sudo rm -f "$INSTALL_PATH"
        print_info "Removed: $INSTALL_PATH"
    fi

    print_info "Uninstall complete."
    exit 0
}

# --- uninstall mode ---
if [[ "$1" == "--uninstall" ]]; then
    uninstall
fi

# --- deps ---
if ! command -v go &> /dev/null; then
    print_error "Go is not installed."
    exit 1
fi

if ! command -v git &> /dev/null; then
    print_error "git is not installed."
    exit 1
fi

print_info "Cloning repository..."
rm -rf "$TMP_DIR"
git clone "$REPO_URL" "$TMP_DIR"
cd "$TMP_DIR"

print_info "Building binary..."
go build -o "$BINARY_NAME" main.go

print_info "Installing binary..."
sudo mv "$BINARY_NAME" "$INSTALL_PATH"
sudo chmod +x "$INSTALL_PATH"

print_info "Creating systemd service..."

sudo bash -c "cat > $SERVICE_PATH <<EOF
[Unit]
Description=SSH SOCKS5 Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_PATH -host=REPLACE_HOST -user=REPLACE_USER -pass=REPLACE_PASS -port=1080
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload

print_info "Enabling service..."

sudo systemctl enable "$SERVICE_NAME"

print_info "Installation completed!"
print_info ""
print_info "IMPORTANT:"
print_info "Edit service config before starting:"
print_info "sudo nano $SERVICE_PATH"
print_info ""
print_info "Then start service:"
print_info "sudo systemctl start $SERVICE_NAME"

rm -rf "$TMP_DIR"
