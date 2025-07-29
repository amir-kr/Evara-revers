#!/bin/bash

# اسکریپت نصب خودکار Evara-revers (مشابه Phantom-Tunnel)
# نصب وابستگی‌ها، rstun، SSL، وب‌سرور و تنظیم سرویس‌ها

# رنگ‌ها برای خروجی زیبا
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # بدون رنگ

echo -e "${GREEN}>>> خوش آمدید به نصب Evara-revers!${NC}"
echo -e "${GREEN}>>> این اسکریپت پنل وب و تونل‌زنی را نصب می‌کند.${NC}"

# بررسی دسترسی root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}خطا: لطفاً این اسکریپت را با دسترسی root اجرا کنید!${NC}"
   echo -e "${RED}مثال: sudo bash <(curl -Ls https://raw.githubusercontent.com/amir-kr/Evara-revers/main/setup-bot.sh)${NC}"
   exit 1
fi

# نصب وابستگی‌های مورد نیاز
echo -e "${GREEN}>>> نصب بسته‌های مورد نیاز...${NC}"
apt-get update
apt-get install -y curl python3 python3-pip sqlite3 nginx socat

# نصب acme.sh برای دریافت گواهی SSL
echo -e "${GREEN}>>> نصب ابزار acme.sh برای SSL...${NC}"
curl https://get.acme.sh | sh
source ~/.bashrc

# درخواست دامنه از کاربر
echo -e "${GREEN}>>> لطفاً دامنه‌ای که به IP سرور شما اشاره می‌کند را وارد کنید (مثل example.com):${NC}"
read -p "دامنه: " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}خطا: وارد کردن دامنه الزامی است!${NC}"
    exit 1
fi

# بررسی DNS دامنه
echo -e "${GREEN}>>> بررسی تنظیمات DNS برای $DOMAIN...${NC}"
IP=$(curl -s http://checkip.amazonaws.com)
DOMAIN_IP=$(dig +short $DOMAIN | tail -n 1)
if [[ "$DOMAIN_IP" != "$IP" ]]; then
    echo -e "${RED}خطا: دامنه $DOMAIN به IP سرور ($IP) اشاره نمی‌کند!${NC}"
    echo -e "${RED}لطفاً رکورد A را در DNS تنظیم کنید و دوباره امتحان کنید.${NC}"
    exit 1
fi

# دریافت گواهی SSL با acme.sh
echo -e "${GREEN}>>> دریافت گواهی SSL برای $DOMAIN...${NC}"
~/.acme.sh/acme.sh --issue -d $DOMAIN --nginx --force

# تنظیم گواهی‌ها
mkdir -p /etc/letsencrypt/$DOMAIN
~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
    --key-file /etc/letsencrypt/$DOMAIN/privkey.pem \
    --fullchain-file /etc/letsencrypt/$DOMAIN/fullchain.pem

# نصب کتابخانه‌های پایتون
echo -e "${GREEN}>>> نصب کتابخانه‌های پایتون...${NC}"
pip3 install flask flask-login gunicorn

# دانلود باینری‌های rstun
echo -e "${GREEN}>>> دانلود هسته تونل‌زنی (rstun)...${NC}"
mkdir -p /usr/local/evara-revers/bin
curl -sSL https://github.com/neevek/rstun/releases/latest/download/rstunc -o /usr/local/evara-revers/bin/rstunc
curl -sSL https://github.com/neevek/rstun/releases/latest/download/rstund -o /usr/local/evara-revers/bin/rstund
chmod +x /usr/local/evara-revers/bin/rstunc
chmod +x /usr/local/evara-revers/bin/rstund

# ایجاد پوشه برای فایل‌های وب
mkdir -p /usr/local/evara-revers/web/templates

# دانلود فایل‌های پروژه از مخزن
echo -e "${GREEN}>>> دانلود فایل‌های پنل وب...${NC}"
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara-revers/main/web/app.py -o /usr/local/evara-revers/web/app.py
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara-revers/main/tunnels.py -o /usr/local/evara-revers/tunnels.py
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara-revers/main/web/templates/login.html -o /usr/local/evara-revers/web/templates/login.html
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara-revers/main/web/templates/dashboard.html -o /usr/local/evara-revers/web/templates/dashboard.html
curl -sSL https://raw.githubusercontent.com/amir-kr/Evara-revers/main/web/templates/monitor.html -o /usr/local/evara-revers/web/templates/monitor.html

# ایجاد دیتابیس SQLite
echo -e "${GREEN}>>> تنظیم دیتابیس برای ذخیره تونل‌ها و کاربران...${NC}"
sqlite3 /usr/local/evara-revers/database.db "CREATE TABLE IF NOT EXISTS tunnels (id INTEGER PRIMARY KEY, name TEXT, type TEXT, port INTEGER, mode TEXT, status TEXT);"
sqlite3 /usr/local/evara-revers/database.db "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT, password TEXT);"
sqlite3 /usr/local/evara-revers/database.db "INSERT OR REPLACE INTO users (id, username, password) VALUES (1, 'admin', 'admin');"

# تنظیم سرویس systemd برای وب‌سرور
echo -e "${GREEN}>>> راه‌اندازی سرویس پنل وب...${NC}"
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
echo -e "${GREEN}>>> راه‌اندازی سرویس هسته تونل‌زنی...${NC}"
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
echo -e "${GREEN}>>> تنظیم وب‌سرور Nginx با SSL...${NC}"
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
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/evara-revers /etc/nginx/sites-enabled/
systemctl restart nginx

# نمایش پیام موفقیت
echo -e "${GREEN}>>> نصب با موفقیت به پایان رسید!${NC}"
echo -e "${GREEN}>>> پنل وب در https://$DOMAIN آماده استفاده است.${NC}"
echo -e "${GREEN}>>> نام کاربری: admin${NC}"
echo -e "${GREEN}>>> رمز عبور: admin${NC}"
echo -e "${GREEN}>>> برای تغییر رمز، دستور زیر را اجرا کنید:${NC}"
echo -e "${GREEN}sqlite3 /usr/local/evara-revers/database.db \"UPDATE users SET password='NEW_PASSWORD' WHERE username='admin';\"${NC}"
echo -e "${GREEN}>>> برای پشتیبانی، به https://github.com/amir-kr/Evara-revers مراجعه کنید.${NC}"
