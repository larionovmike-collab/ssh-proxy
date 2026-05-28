#!/usr/bin/env bash

set -e

BINARY_NAME="ssh-proxy"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"
REPO_URL="https://github.com/larionovmike-collab/ssh-proxy.git"
BUILD_DIR="/tmp/ssh-proxy-build"
SERVICE_NAME="ssh-proxy"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
GO_VERSION="1.22.3"

print_info() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

uninstall() {
    print_info "Остановка и удаление службы systemd..."

    if systemctl list-units --full -all | grep -q "${SERVICE_NAME}.service"; then
        sudo systemctl stop "$SERVICE_NAME" || true
        sudo systemctl disable "$SERVICE_NAME" || true
    fi

    if [ -f "$SERVICE_PATH" ]; then
        sudo rm -f "$SERVICE_PATH"
        print_info "Удален файл службы: $SERVICE_PATH"
    fi

    sudo systemctl daemon-reload || true

    print_info "Удаление бинарного файла..."
    if [ -f "$INSTALL_PATH" ]; then
        sudo rm -f "$INSTALL_PATH"
        print_info "Удален бинарник: $INSTALL_PATH"
    fi

    print_info "Удаление системного пользователя..."
    if id "sshproxy" &>/dev/null; then
        sudo userdel -r sshproxy || true
        print_info "Пользователь sshproxy удален."
    fi

    print_info "Деинсталляция успешно завершена."
    exit 0
}

# --- Режим деинсталляции ---
if [[ "$1" == "--uninstall" ]]; then
    uninstall
fi

# --- Проверка и установка Git ---
if ! command -v git &> /dev/null; then
    print_info "Git не найден. Устанавливаем git через apt..."
    sudo apt update -y
    sudo apt install git -y
else
    print_info "Git уже установлен: $(git --version)"
fi

# Проверка остальных базовых утилит для скачивания Go
for cmd in wget tar; do
    if ! command -v $cmd &> /dev/null; then
        print_info "$cmd не найден. Устанавливаем через apt..."
        sudo apt update -y && sudo apt install $cmd -y
    fi
done

# --- Проверка и установка Go ---
if ! command -v go &> /dev/null; then
    print_info "Go не найден. Начинаем установку Go ${GO_VERSION}..."
    
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        GO_ARCH="amd64"
    elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
        GO_ARCH="arm64"
    else
        print_error "Неподдерживаемая архитектура процессора: $ARCH"
        exit 1
    fi

    print_info "Скачивание архива Go для linux-$GO_ARCH..."
    TMP_GO_DIR=$(mktemp -d)
    wget -q --show-progress "https://golang.org/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -O "$TMP_GO_DIR/go.tar.gz"
    
    print_info "Распаковка Go в /usr/local..."
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "$TMP_GO_DIR/go.tar.gz"
    rm -rf "$TMP_GO_DIR"

    # Экспортируем PATH для текущего процесса установки
    export PATH=$PATH:/usr/local/go/bin

    # Делаем Go доступным глобально в системе для всех пользователей
    if [ ! -f "/etc/profile.d/go.sh" ]; then
        echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/go.sh > /dev/null
        sudo chmod +x /etc/profile.d/go.sh
    fi
else
    print_info "Используется установленная версия: $(go version)"
fi

# --- Клонирование и сборка ---
print_info "Подготовка директории для сборки..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

print_info "Клонирование репозитория $REPO_URL..."
git clone "$REPO_URL" "$BUILD_DIR"
cd "$BUILD_DIR"

print_info "Компиляция проекта из исходников..."
go mod download
go build -o "$BINARY_NAME" main.go

print_info "Установка бинарного файла..."
sudo mv "$BINARY_NAME" "$INSTALL_PATH"
sudo chmod +x "$INSTALL_PATH"

# --- Интерактивная настройка параметров ---
echo ""
print_info "=== Конфигурация параметров SSH SOCKS5 Proxy ==="
read -p "Введи SSH хост (например, 192.168.1.50:22): " PROXY_HOST
read -p "Введи имя пользователя SSH: " PROXY_USER
read -s -p "Введи пароль SSH: " PROXY_PASS
echo ""
read -p "Введи локальный порт SOCKS5 [по умолчанию: 1080]: " PROXY_PORT
PROXY_PORT=${PROXY_PORT:-1080}

if [[ -z "$PROXY_HOST" || -z "$PROXY_USER" || -z "$PROXY_PASS" ]]; then
    print_error "Критическая ошибка: Хост, пользователь и пароль обязательны для заполнения!"
    exit 1
fi

# --- Создание локального изолированного пользователя для демона ---
if ! id "sshproxy" &>/dev/null; then
    print_info "Создание системного пользователя 'sshproxy' для безопасного запуска службы..."
    sudo useradd -r -s /bin/false sshproxy
fi

print_info "Создание демона systemd..."

sudo bash -c "cat > $SERVICE_PATH <<EOF
[Unit]
Description=SSH SOCKS5 Proxy Service
After=network.target

[Service]
Type=simple
User=sshproxy
Group=sshproxy
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/go/bin
ExecStart=$INSTALL_PATH -host=$PROXY_HOST -user=$PROXY_USER -pass=$PROXY_PASS -port=$PROXY_PORT
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF"

# Очистка за собой рабочей папки сборки
cd /
rm -rf "$BUILD_DIR"

print_info "Перезапуск демона systemd и запуск прокси..."
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

print_info "Установка завершена успешно!"
print_info "Логи прокси можно смотреть в реальном времени: sudo journalctl -u $SERVICE_NAME -f"
