#!/bin/bash

# اسکریپت نصب Amir-Tunnel
# نصب وابستگی‌ها، وب‌سرور، rstun و تنظیم سرویس systemd

echo "شروع نصب Amir-Tunnel..."

# نصب وابستگی‌های مورد نیاز
apt-get update
apt-get install -y curl python3 python3-pip sqlite3 nginx
pip3 install flask flask-login gunicorn

# دانلود باینری‌های rstun
mkdir -p /usr/local/amir-tunnel/bin
curl -sSL https://github.com/neevek/rstun/releases/latest/download/rstunc -o /usr/local/amir-tunnel/bin/rstunc
curl -sSL https://github.com/neevek/rstun/releases/latest/download/rstund -o /usr/local/amir-tunnel/bin/rstund
chmod +x /usr/local/amir-tunnel/bin/rstunc
chmod +x /usr/local/amir-tunnel/bin/rstund

# ایجاد پوشه برای فایل‌های وب
mkdir -p /usr/local/amir-tunnel/web/templates

# کپی فایل‌های پروژه
cp -r /root/Amir-Tunnel/web/* /usr/local/amir-tunnel/web/
cp /root/Amir-Tunnel/tunnels.py /usr/local/amir-tunnel/

# ایجاد دیتابیس SQLite
sqlite3 /usr/local/amir-tunnel/database.db "CREATE TABLE IF NOT EXISTS tunnels (id INTEGER PRIMARY KEY, name TEXT, type TEXT, port INTEGER, mode TEXT, status TEXT);"
sqlite3 /usr/local/amir-tunnel/database.db "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT, password TEXT);"
sqlite3 /usr/local/amir-tunnel/database.db "INSERT OR REPLACE INTO users (id, username, password) VALUES (1, 'admin', 'admin');"

# تنظیم سرویس systemd برای وب‌سرور
cat << EOF > /etc/systemd/system/amir-tunnel-web.service
[Unit]
Description=Amir-Tunnel Web Panel
After=network.target

[Service]
ExecStart=/usr/bin/gunicorn --workers 3 --bind 0.0.0.0:5000 -m 007 /usr/local/amir-tunnel/web/app:app
WorkingDirectory=/usr/local/amir-tunnel/web
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی و شروع سرویس
systemctl enable amir-tunnel-web
systemctl start amir-tunnel-web

# تنظیم Nginx برای پروکسی
cat << EOF > /etc/nginx/sites-available/amir-tunnel
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
ln -sf /etc/nginx/sites-available/amir-tunnel /etc/nginx/sites-enabled/
systemctl restart nginx

echo "نصب Amir-Tunnel با موفقیت انجام شد!"
echo "پنل وب در http://<YOUR_SERVER_IP> قابل دسترسی است."
echo "نام کاربری پیش‌فرض: admin"
echo "رمز عبور پیش‌فرض: admin"
echo "برای تغییر رمز، از پنل وب استفاده کنید."
