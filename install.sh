#!/bin/bash
set -e

echo "Instalando sistema Bakken Backend..."

# Detectar versión de Ubuntu (20,22,24)
ver=$(lsb_release -rs | cut -d'.' -f1)
if [[ "$ver" != "20" && "$ver" != "22" && "$ver" != "24" ]]; then
  echo "Versión de Ubuntu no soportada: $ver"
  exit 1
fi

echo "Versión de Ubuntu detectada: $ver"

# Actualizar paquetes e instalar dependencias
apt update && apt upgrade -y
apt install -y python3 python3-pip python3-venv nginx sqlite3 git curl

# Crear entorno virtual e instalar dependencias Python
python3 -m venv /opt/bakken_env
source /opt/bakken_env/bin/activate
pip install --upgrade pip
pip install fastapi uvicorn[standard]

# Crear carpeta del proyecto
mkdir -p /opt/bakken

# Descargar main.py
curl -s -o /opt/bakken/main.py https://raw.githubusercontent.com/VIPNETBR/bakken-backend/main/backend/main.py

# Descargar menu.sh
curl -s -o /opt/bakken/menu.sh https://raw.githubusercontent.com/VIPNETBR/bakken-backend/main/scripts/menu.sh
chmod +x /opt/bakken/menu.sh

# Ajustar path de base de datos en menu.sh
sed -i 's|DB="../backend.db"|DB="/opt/bakken/backend.db"|' /opt/bakken/menu.sh

# Crear base de datos SQLite si no existe
DB_PATH="/opt/bakken/backend.db"
if [ ! -f "$DB_PATH" ]; then
cat > /tmp/create_tables.sql <<EOF
CREATE TABLE IF NOT EXISTS clients (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ip TEXT NOT NULL,
    identifier TEXT NOT NULL,
    fecha_vencimiento TEXT NOT NULL,
    estado INTEGER DEFAULT 1
);
CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
EOF
    sqlite3 "$DB_PATH" < /tmp/create_tables.sql
    echo "Base de datos creada en $DB_PATH."
else
    echo "Base de datos existente detectada en $DB_PATH."
fi

# Crear servicio systemd para Uvicorn (en puerto 5000)
cat > /etc/systemd/system/bakken.service <<EOF
[Unit]
Description=Bakken Backend FastAPI Service
After=network.target

[Service]
User=root
WorkingDirectory=/opt/bakken
Environment="PATH=/opt/bakken_env/bin"
ExecStart=/opt/bakken_env/bin/uvicorn main:app --host 127.0.0.1 --port 5000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Habilitar servicio
systemctl daemon-reload
systemctl enable bakken.service
systemctl start bakken.service

# Configurar Nginx proxy para WebSocket en puerto 80
cat > /etc/nginx/sites-available/bakken <<EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

ln -sf /etc/nginx/sites-available/bakken /etc/nginx/sites-enabled/bakken
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

echo "✅ Instalación completada."
echo "➡ Ejecuta '/opt/bakken/menu.sh' para administrar el sistema."
