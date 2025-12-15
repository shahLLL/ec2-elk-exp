#!/bin/bash
# Install Beats (Filebeat & Metricbeat) on client server

# 1. Install Java and Add Elastic repository key (same as above)
sudo apt update
sudo apt install openjdk-17-jre-headless wget -y
wget -qO - artifacts.elastic.co | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] artifacts.elastic.co stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

# 2. Install Beats
sudo apt update
sudo apt install filebeat metricbeat -y

# 3. Configure Filebeat to send to the ELK server's Logstash input (port 5044)
# Disable ES output, enable Logstash output
sudo sed -i 's/output.elasticsearch:/#output.elasticsearch:/g' /etc/filebeat/filebeat.yml
sudo sed -i 's/#output.logstash:/output.logstash:/g' /etc/filebeat/filebeat.yml
# Set the ELK Server's Private IP using the Terraform injected variable
sudo sed -i 's/#hosts: \["localhost:5044"\]/hosts: \["${elk_server_private_ip}:5044"\]/g' /etc/filebeat/filebeat.yml

# 4. Configure Metricbeat similarly
sudo sed -i 's/output.elasticsearch:/#output.elasticsearch:/g' /etc/metricbeat/metricbeat.yml
sudo sed -i 's/#output.logstash:/output.logstash:/g' /etc/metricbeat/metricbeat.yml
sudo sed -i 's/#hosts: \["localhost:5044"\]/hosts: \["${elk_server_private_ip}:5044"\]/g' /etc/metricbeat/metricbeat.yml

# 5. Enable default system modules
sudo filebeat modules enable system
sudo metricbeat modules enable system

# 6. Start services
sudo systemctl daemon-reload
sudo systemctl enable filebeat metricbeat
sudo systemctl restart filebeat metricbeat
