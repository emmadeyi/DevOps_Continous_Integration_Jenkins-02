#!/bin/bash

# Function to handle errors
handle_error() {
    echo "Error: $1"
    exit 1
}

# Update package list and install OpenJDK 17 and wget
sudo apt update || handle_error "Failed to update package list"
sudo apt install -y openjdk-17-jdk wget || handle_error "Failed to install OpenJDK 17 or wget"

# Verify Java installation
java -version || handle_error "Java installation failed or Java not found"

# Create a user for Nexus
sudo useradd -d /opt/nexus -s /bin/bash nexus || handle_error "Failed to create nexus user"
echo "Please set a password for the nexus user:"
sudo passwd nexus || handle_error "Failed to set password for nexus user"

# Increase the number of open file descriptors
echo "nexus - nofile 65536" | sudo tee /etc/security/limits.d/nexus.conf || handle_error "Failed to set file descriptor limit"

# Set the system limit for the number of open files
sudo sysctl -w fs.file-max=65536 || handle_error "Failed to set system-wide file descriptor limit"

# Download and extract Nexus
cd /tmp || handle_error "Failed to change directory to /tmp"
wget https://download.sonatype.com/nexus/3/latest-unix.tar.gz || handle_error "Failed to download Nexus"
tar xzf latest-unix.tar.gz || handle_error "Failed to extract Nexus archive"

# Move Nexus files to /opt
sudo mv nexus-3.* /opt/nexus || handle_error "Failed to move Nexus files to /opt/nexus"
sudo mv sonatype-work /opt/ || handle_error "Failed to move sonatype-work to /opt"

# Set ownership of Nexus files
sudo chown -R nexus:nexus /opt/nexus /opt/sonatype-work || handle_error "Failed to set ownership of Nexus files"

# Configure Nexus to run as the nexus user
echo 'run_as_user="nexus"' | sudo tee /opt/nexus/bin/nexus.rc || handle_error "Failed to configure Nexus user"

# Configure JVM options for Nexus
cat <<EOT | sudo tee /opt/nexus/bin/nexus.vmoptions || handle_error "Failed to configure Nexus JVM options"
-Xms1024m
-Xmx1024m
-XX:MaxDirectMemorySize=1024m
EOT

# Create a systemd service for Nexus
cat <<EOT | sudo tee /etc/systemd/system/nexus.service || handle_error "Failed to create Nexus systemd service"
[Unit]
Description=Nexus Repository Manager
After=network.target

[Service]
Type=forking
LimitNOFILE=65536
Environment="INSTALL4J_JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"
ExecStart=/opt/nexus/bin/nexus start
ExecStop=/opt/nexus/bin/nexus stop
User=nexus
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOT

# Reload systemd to recognize the new service
sudo systemctl daemon-reload || handle_error "Failed to reload systemd"

# Start and enable Nexus service
sudo systemctl start nexus.service || handle_error "Failed to start Nexus service"
sudo systemctl enable nexus.service || handle_error "Failed to enable Nexus service"

# Check Nexus service status
sudo systemctl status nexus.service || handle_error "Nexus service is not running properly"

# Install Nginx
sudo apt install nginx -y || handle_error "Failed to install Nginx"

# Check if Nginx is enabled and its status
sudo systemctl is-enabled nginx || handle_error "Nginx is not enabled"
sudo systemctl status nginx || handle_error "Nginx service is not running properly"

# Configure Nginx as a reverse proxy for Nexus
cat <<EOT | sudo tee /etc/nginx/sites-available/nexus || handle_error "Failed to configure Nginx for Nexus"
upstream nexus3 {
  server 127.0.0.1:8081;
}

server {
    listen 80;
    server_name domain.name;

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
sudo ln -s /etc/nginx/sites-available/nexus /etc/nginx/sites-enabled/ || handle_error "Failed to enable Nginx site configuration"

# Test the Nginx configuration for errors
sudo nginx -t || handle_error "Nginx configuration test failed"

# Restart Nginx to apply the changes
sudo systemctl restart nginx || handle_error "Failed to restart Nginx"

echo "Nexus Repository Manager and Nginx reverse proxy have been installed and configured successfully."
