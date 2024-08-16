
sudo apt install -y openjdk-17-jdk wget
java -version

sudo useradd -d /opt/nexus -s /bin/bash nexus
sudo passwd nexus

ulimit -n 65536

sudo nano /etc/security/limits.d/nexus.conf
nexus - nofile 65536
wget https://download.sonatype.com/nexus/3/latest-unix.tar.gz
tar xzf latest-unix.tar.gz
mv nexus-3.41.1-01 /opt/nexus
mv sonatype-work /opt/
chown -R nexus:nexus /opt/nexus /opt/sonatype-work
sudo nano /opt/nexus/bin/nexus.rc
run_as_user="nexus"
sudo nano /opt/nexus/bin/nexus.vmoptions
-Xms1024m
-Xmx1024m
-XX:MaxDirectMemorySize=1024m

sudo nano /etc/systemd/system/nexus.service

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


sudo systemctl daemon-reload
sudo systemctl start nexus.service
sudo systemctl enable nexus.service
sudo systemctl status nexus.service
sudo apt install nginx -y
sudo systemctl is-enabled nginx
sudo systemctl status nginx
sudo nano /etc/nginx/sites-available/nexus

upstream nexus3 {
  server 127.0.0.1:8081;
}

server {
    listen 80;
    server_name domain.name;

    location / {
        proxy_pass http://nexus3/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;

        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forward-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forward-Proto http;
        proxy_set_header X-Nginx-Proxy true;

        proxy_redirect off;
    }
}

sudo ln -s /etc/nginx/sites-available/nexus /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx