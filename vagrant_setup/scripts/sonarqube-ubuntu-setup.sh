# Provision SonarQube on the sonarqube VM
sonarqube.vm.provision "shell", inline: <<-SHELL
  #!/bin/bash

  # Exit on any error
  set -e

  # Backup and update sysctl.conf
  if [ -f /etc/sysctl.conf ]; then
    cp /etc/sysctl.conf /root/sysctl.conf_backup
  else
    echo "sysctl.conf not found, creating a new one."
  fi

  cat <<EOT > /etc/sysctl.conf
  vm.max_map_count=262144
  fs.file-max=65536
  ulimit -n 65536
  ulimit -u 4096
  EOT

  # Backup and update limits.conf
  if [ -f /etc/security/limits.conf ]; then
    cp /etc/security/limits.conf /root/sec_limit.conf_backup
  else
    echo "limits.conf not found, creating a new one."
  fi

  cat <<EOT > /etc/security/limits.conf
  sonarqube   -   nofile   65536
  sonarqube   -   nproc    4096
  EOT

  # Install and configure Java
  sudo apt-get update -y
  sudo apt-get install -y openjdk-11-jdk
  sudo update-alternatives --config java
  if java -version; then
    echo "Java installed successfully."
  else
    echo "Java installation failed." >&2
    exit 1
  fi

  # Configure PostgreSQL
  sudo apt-get update
  if wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | sudo apt-key add -; then
    echo "PostgreSQL key added successfully."
  else
    echo "Failed to add PostgreSQL key." >&2
    exit 1
  fi

  sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" >> /etc/apt/sources.list.d/pgdg.list'
  sudo apt-get install -y postgresql postgresql-contrib
  sudo systemctl enable postgresql.service
  sudo systemctl start postgresql.service

  if systemctl is-active --quiet postgresql; then
    echo "PostgreSQL started successfully."
  else
    echo "Failed to start PostgreSQL." >&2
    exit 1
  fi

  echo "postgres:admin123" | sudo chpasswd
  runuser -l postgres -c "createuser sonar"

  sudo -i -u postgres psql -c "ALTER USER sonar WITH ENCRYPTED PASSWORD 'admin123';"
  sudo -i -u postgres psql -c "CREATE DATABASE sonarqube OWNER sonar;"
  sudo -i -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE sonarqube to sonar;"
  sudo systemctl restart postgresql

  if netstat -tulpena | grep postgres; then
    echo "PostgreSQL is running."
  else
    echo "PostgreSQL is not running." >&2
    exit 1
  fi

  # Install and configure SonarQube
  sudo mkdir -p /sonarqube/
  cd /sonarqube/
  sudo curl -O https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-8.3.0.34182.zip

  if [ -f sonarqube-8.3.0.34182.zip ]; then
    sudo apt-get install -y zip
    sudo unzip -o sonarqube-8.3.0.34182.zip -d /opt/
    sudo mv /opt/sonarqube-8.3.0.34182/ /opt/sonarqube
  else
    echo "SonarQube archive not found or download failed." >&2
    exit 1
  fi

  if id "sonar" &>/dev/null; then
    echo "User 'sonar' already exists."
  else
    sudo groupadd sonar
    sudo useradd -c "SonarQube - User" -d /opt/sonarqube/ -g sonar sonar
  fi

  sudo chown sonar:sonar /opt/sonarqube/ -R

  if [ -f /opt/sonarqube/conf/sonar.properties ]; then
    cp /opt/sonarqube/conf/sonar.properties /root/sonar.properties_backup
  else
    echo "sonar.properties not found, creating a new one."
  fi

  cat <<EOT > /opt/sonarqube/conf/sonar.properties
  sonar.jdbc.username=sonar
  sonar.jdbc.password=admin123
  sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube
  sonar.web.host=0.0.0.0
  sonar.web.port=9000
  sonar.web.javaAdditionalOpts=-server
  sonar.search.javaOpts=-Xmx512m -Xms512m -XX:+HeapDumpOnOutOfMemoryError
  sonar.log.level=INFO
  sonar.path.logs=logs
  EOT

  # Create and enable SonarQube service
  cat <<EOT > /etc/systemd/system/sonarqube.service
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

  sudo systemctl daemon-reload
  sudo systemctl enable sonarqube.service

  # Install and configure Nginx
  sudo apt-get install -y nginx
  sudo rm -rf /etc/nginx/sites-enabled/default
  sudo rm -rf /etc/nginx/sites-available/default

  cat <<EOT > /etc/nginx/sites-available/sonarqube
  server {
      listen      80;
      server_name sonarqube.groophy.in;

      access_log  /var/log/nginx/sonar.access.log;
      error_log   /var/log/nginx/sonar.error.log;

      proxy_buffers 16 64k;
      proxy_buffer_size 128k;

      location / {
          proxy_pass  http://127.0.0.1:9000;
          proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
          proxy_redirect off;
          
          proxy_set_header    Host            \$host;
          proxy_set_header    X-Real-IP       \$remote_addr;
          proxy_set_header    X-Forwarded-For \$proxy_add_x_forwarded_for;
          proxy_set_header    X-Forwarded-Proto http;
      }
  }
  EOT

  sudo ln -s /etc/nginx/sites-available/sonarqube /etc/nginx/sites-enabled/sonarqube
  sudo systemctl enable nginx.service

  # Configure firewall
  sudo ufw allow 80,9000,9001/tcp

  echo "System reboot in 30 sec"
  sleep 30
  sudo reboot
SHELL
end