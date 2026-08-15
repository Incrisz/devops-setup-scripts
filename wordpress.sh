#!/bin/bash

# Run this script as root on a fresh Ubuntu server.
# Before running it on another server, change the domain below.

set -e
export DEBIAN_FRONTEND=noninteractive

DOMAIN="wordp.bmp.com.ng"
DB_NAME="wordpress"
DB_USER="wordpress_user"
DB_PASSWORD=$(openssl rand -hex 24)

# Update Ubuntu and install Nginx, MariaDB, PHP, and Certbot.
apt-get update
apt-get install -y nginx mariadb-server php-fpm php-mysql php-curl php-gd php-xml php-mbstring php-zip php-intl php-imagick unzip curl ufw certbot python3-certbot-nginx

# Start the required services now and after every reboot.
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
systemctl enable --now nginx
systemctl enable --now mariadb
systemctl enable --now php${PHP_VERSION}-fpm

# Remove MariaDB's default test data and create the WordPress database.
mariadb -e "DELETE FROM mysql.user WHERE User='';"
mariadb -e "DROP DATABASE IF EXISTS test;"
mariadb -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mariadb -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mariadb -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
mariadb -e "ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
mariadb -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mariadb -e "FLUSH PRIVILEGES;"

# Download and unpack WordPress.
curl -L https://wordpress.org/latest.tar.gz -o /tmp/wordpress.tar.gz
tar -xzf /tmp/wordpress.tar.gz -C /var/www

# Add the database details to WordPress.
cp /var/www/wordpress/wp-config-sample.php /var/www/wordpress/wp-config.php
sed -i "s/database_name_here/$DB_NAME/" /var/www/wordpress/wp-config.php
sed -i "s/username_here/$DB_USER/" /var/www/wordpress/wp-config.php
sed -i "s/password_here/$DB_PASSWORD/" /var/www/wordpress/wp-config.php

# Replace the example security keys with fresh WordPress keys.
curl -sS https://api.wordpress.org/secret-key/1.1/salt/ -o /tmp/wordpress-salts.txt
sed -i "/put your unique phrase here/d" /var/www/wordpress/wp-config.php
sed -i "/table_prefix/r /tmp/wordpress-salts.txt" /var/www/wordpress/wp-config.php

# Set safe file ownership and permissions.
chown -R www-data:www-data /var/www/wordpress
find /var/www/wordpress -type d -exec chmod 755 {} \;
find /var/www/wordpress -type f -exec chmod 644 {} \;
chmod 640 /var/www/wordpress/wp-config.php

# Find the installed PHP-FPM socket.
PHP_SOCKET=$(find /run/php -name "php*-fpm.sock" | head -n 1)

# Create the Nginx site configuration.
tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN;
    root /var/www/wordpress;
    index index.php index.html;

    client_max_body_size 64M;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCKET;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Enable the WordPress site and reload Nginx.
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
unlink /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t
systemctl reload nginx

# Allow web traffic if UFW is in use.
ufw allow 'Nginx Full'

# Add a free HTTPS certificate and redirect HTTP to HTTPS.
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email --redirect

# Keep a root-only copy of the generated database credentials on the server.
printf "Database: %s\nUser: %s\nPassword: %s\n" "$DB_NAME" "$DB_USER" "$DB_PASSWORD" > /root/wordpress-db-credentials.txt
chmod 600 /root/wordpress-db-credentials.txt

# Final checks.
nginx -t
systemctl is-active nginx
systemctl is-active mariadb
systemctl is-active php${PHP_VERSION}-fpm
curl -I https://$DOMAIN

echo "WordPress is ready at https://$DOMAIN"
