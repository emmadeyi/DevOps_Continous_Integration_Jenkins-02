#!/bin/bash
  # Update package index
  sudo apt update
  # Install dependencies
  sudo apt install -y fontconfig openjdk-17-jre maven wget
  # Add Jenkins repository key to the system
  sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
  # Add Jenkins repository to the sources list
  echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
  # Update package index again to include Jenkins repository
  sudo apt-get update
  # Install Jenkins
  sudo apt-get install -y jenkins
  # Start and enable Jenkins service
  sudo systemctl start jenkins
  sudo systemctl enable jenkins
  # Verify Jenkins installation
  if systemctl is-active --quiet jenkins; then
      echo "Jenkins installed and running successfully."
  else
      echo "Failed to start Jenkins." >&2
      exit 1
  fi
  # Configure firewall (if applicable)
  sudo ufw allow 8080/tcp
  # Output Jenkins initial admin password for setup
  echo "Jenkins initial admin password:"
  sudo cat /var/lib/jenkins/secrets/initialAdminPassword