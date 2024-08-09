#!/bin/bash

# Exit on any error
set -e

# Install Java and wget
yum install -y java-1.8.0-openjdk.x86_64 wget

# Create necessary directories
mkdir -p /opt/nexus/ /tmp/nexus/

# Download Nexus
cd /tmp/nexus/
NEXUS_URL="https://download.sonatype.com/nexus/3/latest-unix.tar.gz"
wget -O nexus.tar.gz $NEXUS_URL

# Extract the Nexus tarball
tar -xzvf nexus.tar.gz
NEXUS_DIR=$(tar -tzf nexus.tar.gz | head -1 | cut -f1 -d"/")

# Move Nexus to the installation directory
mv $NEXUS_DIR/* /opt/nexus/

# Clean up the temporary files
rm -rf /tmp/nexus/nexus.tar.gz /tmp/nexus/$NEXUS_DIR

# Create a nexus user
useradd -r -d /opt/nexus -s /bin/false nexus
chown -R nexus:nexus /opt/nexus

# Create systemd service file for Nexus
cat <<EOT > /etc/systemd/system/nexus.service
[Unit]
Description=Nexus Repository Manager
After=network.target

[Service]
Type=forking
LimitNOFILE=65536
ExecStart=/opt/nexus/bin/nexus start
ExecStop=/opt/nexus/bin/nexus stop
User=nexus
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOT

# Configure Nexus to run as the nexus user
echo 'run_as_user="nexus"' > /opt/nexus/bin/nexus.rc

# Reload systemd to apply the new service file
systemctl daemon-reload

# Start and enable Nexus service
systemctl start nexus
systemctl enable nexus