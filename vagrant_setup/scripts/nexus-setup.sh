#!/bin/bash

# Exit on any error
set -e

# Variables
NEXUS_VERSION="3.41.1-01"  # Update with the latest version if needed
NEXUS_USER="nexus"
INSTALL_DIR="/opt/nexus"
DATA_DIR="/opt/sonatype-work"
DOWNLOAD_URL="https://download.sonatype.com/nexus/3/nexus-${NEXUS_VERSION}-unix.tar.gz"
JAVA_PACKAGE="openjdk-17-jdk"

# Update system and install Java
echo "Updating system and installing Java..."
sudo apt update
sudo apt install -y $JAVA_PACKAGE wget
sudo apt install -y openjdk-17-jdk wget

# Create nexus user
echo "Creating Nexus user..."
sudo useradd -r -m -d $INSTALL_DIR -s /bin/bash $NEXUS_USER

# Download and extract Nexus
echo "Downloading and installing Nexus..."
sudo mkdir -p $INSTALL_DIR
sudo mkdir -p $DATA_DIR
wget $DOWNLOAD_URL -O /tmp/nexus.tar.gz
sudo tar -xzf /tmp/nexus.tar.gz -C /opt
sudo mv /opt/nexus-${NEXUS_VERSION}/* $INSTALL_DIR/
sudo chown -R $NEXUS_USER:$NEXUS_USER $INSTALL_DIR $DATA_DIR

# Configure Nexus to run as a service
echo "Configuring Nexus service..."
sudo bash -c "cat > /etc/systemd/system/nexus.service" <<EOF
[Unit]
Description=Nexus Repository Manager
After=network.target

[Service]
Type=forking
LimitNOFILE=65536
Environment="INSTALL4J_JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"
ExecStart=${INSTALL_DIR}/bin/nexus start
ExecStop=${INSTALL_DIR}/bin/nexus stop
User=${NEXUS_USER}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the Nexus service
echo "Enabling and starting Nexus service..."
sudo systemctl daemon-reload
sudo systemctl enable nexus.service
sudo systemctl start nexus.service

# Check Nexus service status
echo "Checking Nexus service status..."
sudo systemctl status nexus.service

# Output success message
echo "Nexus Repository Manager installed successfully!"
echo "Access Nexus at http://<your-server-ip>:8081"
