#!/bin/bash

# اسکریپت نصب خودکار Evara-revers
# نصب وابستگی‌ها، rstun، SSL، وب‌سرور و تنظیم سرویس systemd

echo "شروع نصب Evara-revers..."

# بررسی دسترسی root
if [[ $EUID -ne 0 ]]; then
   echo "این اسکریپت باید با دسترسی root اجرا شود!"
   exit 1
fi

# نصب وابستگی‌های مورد نیاز
apt-get update
apt-get install -y curl python3 python3-pip sqlite3 nginx socat

# نصب acme.sh برای دریافت گواهی SSL
echo "نصب acme.sh برای دریافت گواهی SSL..."
curl https://get.acme.sh | sh
source ~/.bashrc

# درخواست دامنه از کاربر
read -p "لطفاً دامنه خود را وارد کنید (مثل example.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    echo "دامنه الزامی است!"
    exit 1
fi

# دریافت گواهی SSL با acme.sh
~/.acme.sh/acme.sh --issue -d $DOMAIN --nginx --force

# تنظیم گواهی‌ها
mkdir -p /etc/letsencrypt/$DOMAIN
~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
    --key-file /etc/letsencrypt/$DOMAIN/privkey.pem \
    --fullchain-file /etc/letsencrypt/$DOMAIN/fullchain.pem

# نصب pip و کتابخانه‌های پایتون
pip3 install flask flask-login gunicorn

# دانلود باینری‌های rstun
mkdir -p /usr/local/evara-revers/bin
curl -sSL https://github.com/neevek/rstun/releases/latest/download/rstunc -o /usr/local/evara-revers/bin/rstunc
curl -sSL https://github.com/neevek/rstun/releases/latest/download/rstund -o /usr/local/evara-revers/bin/rstund
chmod +x /usr/local/evara-revers/bin/rstunc
chmod +x /usr/local/evara-revers/bin/rstund

# ایجاد پوشه برای فایل‌های وب
mkdir -p /usr/local/evara-revers/web/templates

# دانلود فایل‌های پروژه از مخزن
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara-revers/main/web/app.py -o /usr/local/evara-revers/web/app.py
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara-revers/main/tunnels.py -o /usr/local/evara-revers/tunnels.py
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara-revers/main/web/templates/login.html -o /usr/local/evara-revers/web/templates/login.html
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara-revers/main/web/templates/dashboard.html -o /usr/local/evara-revers/web/templates/dashboard.html
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara-revers/main/web/templates/monitor.html -o /usr/local/evara-revers/web/templates/monitor.html

# ایجاد دیتابیس SQLite
sqlite3 /usr/local/evara-revers/database.db "CREATE TABLE IF NOT EXISTS tunnels (id INTEGER PRIMARY KEY, name TEXT, type TEXT, port INTEGER, mode TEXT, status TEXT);"
sqlite3 /usr/local/evara-revers/database.db "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT, password TEXT);"
sqlite3 /usr/local/evara-revers/database.db "INSERT OR REPLACE INTO users (id, username, password) VALUES (1, 'admin', 'admin');"

# تنظیم سرویس systemd برای وب‌سرور
cat << EOF > /etc/systemd/system/evara-revers-web.service
[Unit]
Description=Evara-revers Web Panel
After=network.target

[Service]
ExecStart=/usr/bin/gunicorn --workers 3 --bind 0.0.0.0:5000 -m 007 /usr/local/evara-revers/web/app:app
WorkingDirectory=/usr/local/evara-revers/web
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی و شروع سرویس وب
systemctl enable evara-revers-web
systemctl start evara-revers-web

# تنظیم سرویس systemd برای rstund
cat << EOF > /etc/systemd/system/evara-revers-rstund.service
[Unit]
Description=Evara-revers rstund Server
After=network.target

[Service]
ExecStart=/usr/local/evara-revers/bin/rstund --addr 0.0.0.0:9000 --password 123456
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی و شروع سرویس rstund
systemctl enable evara-revers-rstund
systemctl start evara-revers-rstund

# تنظیم Nginx با SSL
cat << EOF > /etc/nginx/sites-available/evara-revers
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$
