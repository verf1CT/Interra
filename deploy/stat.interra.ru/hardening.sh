#!/bin/bash
# ==============================================================================
# Скрипт безопасной изоляции Apache 2.2 и настройки Nginx Reverse Proxy
# Сервер: stat.interra.ru (биллинг NetUP UTM5)
# ==============================================================================
set -euo pipefail

echo "==> [1/6] Проверка прав root..."
if [ "$EUID" -ne 0 ]; then
  echo "ОШИБКА: Запустите скрипт от пользователя root (sudo bash hardening.sh)"
  exit 1
fi

echo "==> [2/6] Создание резервной копии конфигураций Apache..."
BACKUP_DIR="/root/backup_apache_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -a /etc/apache2 "$BACKUP_DIR/"
echo "Резервная копия сохранена в $BACKUP_DIR"

echo "==> [3/6] Проверка и установка Nginx и Certbot..."
if ! command -v nginx >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y nginx certbot
fi

echo "==> [4/6] Перевод Apache на локальный порт 127.0.0.1:8080..."
# Меняем ports.conf
cat << 'EOF' > /etc/apache2/ports.conf
Listen 127.0.0.1:8080
EOF

# Включаем скрытие сигнатур в security.conf
if [ -f /etc/apache2/conf.d/security ]; then
  sed -i 's/^ServerTokens .*/ServerTokens Prod/' /etc/apache2/conf.d/security
  sed -i 's/^ServerSignature .*/ServerSignature Off/' /etc/apache2/conf.d/security
elif [ -f /etc/apache2/conf-available/security.conf ]; then
  sed -i 's/^ServerTokens .*/ServerTokens Prod/' /etc/apache2/conf-available/security.conf
  sed -i 's/^ServerSignature .*/ServerSignature Off/' /etc/apache2/conf-available/security.conf
fi

# Проверка конфигурации Apache
if ! apache2ctl configtest >/dev/null 2>&1; then
  echo "ВНИМАНИЕ: Проверьте VirtualHost в Apache, чтобы порт совпадал с 8080 (или *:8080)"
fi

echo "==> [5/6] Установка защищённой конфигурации Nginx..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/nginx-stat.interra.ru.conf" /etc/nginx/sites-available/stat.interra.ru.conf
ln -sf /etc/nginx/sites-available/stat.interra.ru.conf /etc/nginx/sites-enabled/

# Проверяем наличие SSL-сертификата
if [ ! -d "/etc/letsencrypt/live/stat.interra.ru" ]; then
  echo "Сертификат Let's Encrypt для stat.interra.ru не найден."
  echo "Выпускаем сертификат через certbot standalone/webroot..."
  certbot certonly --webroot -w /var/www/html -d stat.interra.ru --non-interactive --agree-tos -m noc@interra.ru || true
fi

# Проверка синтаксиса Nginx
nginx -t

echo "==> [6/6] Перезапуск сервисов..."
service apache2 restart || systemctl restart apache2
service nginx reload || systemctl reload nginx

echo ""
echo "=============================================================================="
echo "УСПЕШНО: Apache 2.2 надёжно спрятан за Nginx!"
echo "• Снаружи теперь работает Nginx с TLS 1.2 / TLS 1.3 и HSTS"
echo "• Прямой доступ к Apache из интернета закрыт (слушает только 127.0.0.1:8080)"
echo "• Сигнатуры версий скрыты от сканеров"
echo "=============================================================================="
