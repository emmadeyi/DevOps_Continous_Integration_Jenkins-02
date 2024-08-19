#!/bin/bash

# Backup and update sysctl.conf
cp /etc/sysctl.conf /root/sysctl.conf_backup
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
echo "fs.file-max=65536" >> /etc/sysctl.conf
echo "ulimit -n 65536" >> /etc/sysctl.conf
echo "ulimit -u 4096" >> /etc/sysctl.conf

# Backup and update security limits
cp /etc/security/limits.conf /root/sec_limit.conf_backup
echo "sonarqube   -   nofile   65536" >> /etc/security/limits.conf
echo "sonarqube   -   nproc    4096" >> /etc/security/limits.conf

# Install OpenJDK 11
sudo apt-get update -y
sudo apt-get install openjdk-11-jdk -y
sudo update-alternatives --config java
java -version

# Install PostgreSQL
sudo apt-get update
wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | sudo apt-key add -
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" >> /etc/apt/sources.list.d/pgdg.list'
sudo apt-get update
sudo apt-get install postgresql postgresql-contrib -y
sudo systemctl enable postgresql.service
sudo systemctl start postgresql.service

# Set PostgreSQL password and create sonar user and database
read -sp 'Enter PostgreSQL password for postgres user: ' postgres_password
echo "postgres:$postgres_password" | sudo chpasswd
sudo -u postgres createuser sonar
sudo -i -u postgres psql -c "ALTER USER sonar WITH ENCRYPTED PASSWORD '$postgres_password';"
sudo -i -u postgres psql -c "CREATE DATABASE sonarqube OWNER sonar;"
sudo -i -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE sonarqube TO sonar;"
sudo systemctl restart postgresql

# Check PostgreSQL status
netstat -tulpena | grep postgres

# Download and install SonarQube
sudo mkdir -p /sonarqube/
sudo wget -P /sonarqube/ https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-8.3.0.34182.zip
sudo apt-get install zip -y
sudo unzip -o /sonarqube/sonarqube-8.3.0.34182.zip -d /opt/
sudo mv /opt/sonarqube-8.3.0.34182/ /opt/sonarqube

# Create SonarQube user and set permissions
sudo groupadd sonar
sudo useradd -c "SonarQube - User" -d /opt/sonarqube/ -g sonar sonar
sudo chown sonar:sonar /opt/sonarqube/ -R

# Backup and configure sonar.properties
cp /opt/sonarqube/conf/sonar.properties /root/sonar.properties_backup
cat <<EOT> /opt/sonarqube/conf/sonar.properties
sonar.jdbc.username=sonar
sonar.jdbc.password=$postgres_password
sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube
sonar.web.host=0.0.0.0
sonar.web.port=9000
sonar.web.javaAdditionalOpts=-server
sonar.search.javaOpts=-Xmx512m -Xms512m -XX:+HeapDumpOnOutOfMemoryError
sonar.log.level=INFO
sonar.path.logs=logs
EOT

# Create SonarQube service
cat <<EOT> /etc/systemd/system/sonarqube.service
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=forking

ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop

User=sonar
Group=sonar
Restart=always

LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOT

# Reload systemd, enable and start SonarQube service
sudo systemctl daemon-reload
sudo systemctl enable sonarqube.service

# Install and configure Nginx
sudo apt-get install nginx -y
sudo rm -rf /etc/nginx/sites-enabled/default
sudo rm -rf /etc/nginx/sites-available/default
cat <<EOT> /etc/nginx/sites-available/sonarqube

server{
    listen      80;
    server_name 192.168.10.15;  # Update this IP to match your server's IP or domain

    access_log  /var/log/nginx/sonar.access.log;
    error_log   /var/log/nginx/sonar.error.log;

    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    location / {
        proxy_pass  http://127.0.0.1:9000;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_redirect off;

        proxy_set_header    Host            \$http_host;
        proxy_set_header    X-Real-IP       \$remote_addr;
        proxy_set_header    X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto \$scheme;
    }
}
EOT

sudo ln -s /etc/nginx/sites-available/sonarqube /etc/nginx/sites-enabled/sonarqube
sudo systemctl enable nginx.service
sudo systemctl restart nginx.service

# Configure firewall to allow necessary ports
sudo ufw allow 80,9000/tcp

# Optional reboot with prompt
read -p "Reboot the system in 30 seconds? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "System reboot in 30 sec"
    sleep 30
    sudo reboot
else
    echo "Reboot canceled."
fi
