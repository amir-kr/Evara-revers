#!/bin/bash

# اسکریپت نصب خودکار Evara_Tunnel
# نصب وابستگی‌ها، rstun، SSL، وب‌سرور و تنظیم سرویس systemd

echo "شروع نصب Evara_Tunnel..."

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
mkdir -p /usr/local/evara-tunnel/bin
curl -sSL https://github.com/neevek/rstun/releases/latest/download/rstunc -o /usr/local/evara-tunnel/bin/rstunc
curl -sSL https://github.com/neevek/rstun/releases/latest/download/rstund -o /usr/local/evara-tunnel/bin/rstund
chmod +x /usr/local/evara-tunnel/bin/rstunc
chmod +x /usr/local/evara-tunnel/bin/rstund

# ایجاد پوشه برای فایل‌های وب
mkdir -p /usr/local/evara-tunnel/web/templates

# دانلود فایل‌های پروژه از مخزن
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara_Tunnel/main/web/app.py -o /usr/local/evara-tunnel/web/app.py
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara_Tunnel/main/tunnels.py -o /usr/local/evara-tunnel/tunnels.py
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara_Tunnel/main/web/templates/login.html -o /usr/local/evara-tunnel/web/templates/login.html
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara_Tunnel/main/web/templates/dashboard.html -o /usr/local/evara-tunnel/web/templates/dashboard.html
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara_Tunnel/main/web/templates/monitor.html -o /usr/local/evara-tunnel/web/templates/monitor.html

# ایجاد دیتابیس SQLite
sqlite3 /usr/local/evara-tunnel/database.db "CREATE TABLE IF NOT EXISTS tunnels (id INTEGER PRIMARY KEY, name TEXT, type TEXT, port INTEGER, mode TEXT, status TEXT);"
sqlite3 /usr/local/evara-tunnel/database.db "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT, password TEXT);"
sqlite3 /usr/local/evara-tunnel/database.db "INSERT OR REPLACE INTO users (id, username, password) VALUES (1, 'admin', 'admin');"

# تنظیم سرویس systemd برای وب‌سرور
cat << EOF > /etc/systemd/system/evara-tunnel-web.service
[Unit]
Description=Evara_Tunnel Web Panel
After=network.target

[Service]
ExecStart=/usr/bin/gunicorn --workers 3 --bind 0.0.0.0:5000 -m 007 /usr/local/evara-tunnel/web/app:app
WorkingDirectory=/usr/local/evara-tunnel/web
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی و شروع سرویس وب
systemctl enable evara-tunnel-web
systemctl start evara-tunnel-web

# تنظیم سرویس systemd برای rstund
cat << EOF > /etc/systemd/system/evara-tunnel-rstund.service
[Unit]
Description=Evara_Tunnel rstund Server
After=network.target

[Service]
ExecStart=/usr/local/evara-tunnel/bin/rstund --addr 0.0.0.0:9000 --password 123456
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی و شروع سرویس rstund
systemctl enable evara-tunnel-rstund
systemctl start evara-tunnel-rstund

# تنظیم Nginx با SSL
cat << EOF > /etc/nginx/sites-available/evara-tunnel
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
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/evara-tunnel /etc/nginx/sites-enabled/
systemctl restart nginx

echo "نصب Evara_Tunnel با موفقیت انجام شد!"
echo "پنل وب در https://$DOMAIN قابل دسترسی است."
echo "نام کاربری پیش‌فرض: admin"
echo "رمز عبور پیش‌فرض: admin"
echo "برای تغییر رمز، دیتابیس SQLite را ویرایش کنید یا از پشتیبانی بخواهید."
