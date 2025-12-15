#!/bin/bash
# Install ELK Stack (Ubuntu 22.04)

# 1. Install Java
sudo apt update
sudo apt install openjdk-17-jre-headless wget -y

# 2. Add Elastic repository key
wget -qO - artifacts.elastic.co | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] artifacts.elastic.co stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

# 3. Install ELK components
sudo apt update
sudo apt install elasticsearch logstash kibana -y

# 4. Configure Elasticsearch (Bind to internal IP/localhost)
sudo sed -i 's/#network.host: 0.0.0.0/network.host: 0.0.0.0/g' /etc/elasticsearch/elasticsearch.yml
# In an enterprise setting you would configure security/TLS here, but for this project we disable basic security
sudo sed -i 's/#xpack.security.enabled: true/xpack.security.enabled: false/g' /etc/elasticsearch/elasticsearch.yml

# 5. Configure Kibana (Bind to internal IP, connect to ES)
sudo sed -i 's/#server.host: "localhost"/server.host: "0.0.0.0"/g' /etc/kibana/kibana.yml
sudo sed -i 's/#elasticsearch.hosts: \["http:\/\/localhost:9200"\]/elasticsearch.hosts: \["http:\/\/localhost:9200"\]/g' /etc/kibana/kibana.yml

# 6. Start services
sudo systemctl daemon-reload
sudo systemctl enable elasticsearch kibana logstash
sudo systemctl restart elasticsearch kibana logstash
