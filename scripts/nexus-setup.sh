#!/bin/bash

# Variables
JAVA_PACKAGE="openjdk-17-jdk"
NEXUS_USER="nexus"
NEXUS_INSTALL_DIR="/opt/nexus"
NEXUS_WORK_DIR="/opt/sonatype-work"
NEXUS_SERVICE_FILE="/etc/systemd/system/nexus.service"
NEXUS_DOWNLOAD_URL="https://download.sonatype.com/nexus/3/latest-unix.tar.gz"
NGINX_CONF_FILE="/etc/nginx/sites-available/nexus"
DOMAIN_NAME="your.domain.name"  # Replace with your domain name or IP
JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"

# Function for error handling
error_exit() {
  echo "Error: $1"
  exit 1
}

# Update package lists
sudo apt update || error_exit "Failed to update package lists"

# Install Java and wget
sudo apt install -y "$JAVA_PACKAGE" wget || error_exit "Failed to install $JAVA_PACKAGE and wget"

# Verify Java installation
java -version || error_exit "Java installation failed"

# Create Nexus user
sudo useradd -r -m -d "$NEXUS_INSTALL_DIR" -s /bin/bash "$NEXUS_USER" || error_exit "Failed to create Nexus user"
echo "Please set a password for the Nexus user:"
sudo passwd "$NEXUS_USER" || error_exit "Failed to set password for Nexus user"

# Set system limits for the Nexus user
echo "$NEXUS_USER - nofile 65536" | sudo tee /etc/security/limits.d/nexus.conf || error_exit "Failed to set file limits"
sudo sysctl -w fs.file-max=65536 || error_exit "Failed to set fs.file-max"

# Download and extract Nexus
cd /tmp || error_exit "Failed to change directory to /tmp"
wget "$NEXUS_DOWNLOAD_URL" -O latest-unix.tar.gz || error_exit "Failed to download Nexus"
tar xzf latest-unix.tar.gz || error_exit "Failed to extract Nexus"

# Move Nexus files
sudo mv nexus-3.* "$NEXUS_INSTALL_DIR" || error_exit "Failed to move Nexus installation"
sudo mv sonatype-work "$NEXUS_WORK_DIR" || error_exit "Failed to move Nexus work directory"

# Set ownership of Nexus files
sudo chown -R "$NEXUS_USER":"$NEXUS_USER" "$NEXUS_INSTALL_DIR" "$NEXUS_WORK_DIR" || error_exit "Failed to set ownership"

# Configure Nexus to run as the nexus user
echo "run_as_user=\"$NEXUS_USER\"" | sudo tee "$NEXUS_INSTALL_DIR/bin/nexus.rc" || error_exit "Failed to configure Nexus user"

# Configure JVM options for Nexus
cat <<EOT | sudo tee "$NEXUS_INSTALL_DIR/bin/nexus.vmoptions" || error_exit "Failed to configure Nexus JVM options"
-Xms1024m
-Xmx1024m
-XX:MaxDirectMemorySize=1024m
EOT

# Create a systemd service for Nexus
cat <<EOT | sudo tee "$NEXUS_SERVICE_FILE" || error_exit "Failed to create Nexus systemd service"
[Unit]
Description=Nexus Repository Manager
After=network.target

[Service]
Type=forking
LimitNOFILE=65536
Environment="INSTALL4J_JAVA_HOME=$JAVA_HOME"
ExecStart=$NEXUS_INSTALL_DIR/bin/nexus start
ExecStop=$NEXUS_INSTALL_DIR/bin/nexus stop
User=$NEXUS_USER
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOT

# Reload systemd to recognize the new service
sudo systemctl daemon-reload || error_exit "Failed to reload systemd"

# Start and enable Nexus service
sudo systemctl start nexus.service || error_exit "Failed to start Nexus service"
sudo systemctl enable nexus.service || error_exit "Failed to enable Nexus service"

# Check Nexus service status
sudo systemctl status nexus.service || error_exit "Nexus service status check failed"

# Install Nginx
sudo apt install nginx -y || error_exit "Failed to install Nginx"

# Check if Nginx is enabled and its status
sudo systemctl is-enabled nginx || error_exit "Failed to check if Nginx is enabled"
sudo systemctl status nginx || error_exit "Nginx service status check failed"

# Configure Nginx as a reverse proxy for Nexus
cat <<EOT | sudo tee "$NGINX_CONF_FILE" || error_exit "Failed to create Nginx configuration"
upstream nexus3 {
  server 127.0.0.1:8081;
}

server {
    listen 80;
    server_name $DOMAIN_NAME;

    location / {
        proxy_pass http://nexus3/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;

        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forward-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forward-Proto http;
        proxy_set_header X-Nginx-Proxy true;

        proxy_redirect off;
    }
}
EOT

# Enable the Nginx site configuration
sudo ln -s "$NGINX_CONF_FILE" /etc/nginx/sites-enabled/ || error_exit "Failed to enable Nginx site configuration"

# Test the Nginx configuration for errors
sudo nginx -t || error_exit "Nginx configuration test failed"

# Restart Nginx to apply the changes
sudo systemctl restart nginx || error_exit "Failed to restart Nginx"

echo "Nexus Repository Manager and Nginx reverse proxy have been installed and configured successfully."
