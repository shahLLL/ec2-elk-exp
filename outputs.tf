output "elk_server_public_ip" {
  value = aws_instance.elk_server.public_ip
}

output "kibana_url" {
  value = "http://${aws_instance.elk_server.public_ip}:5601"
}

output "client_public_ip" {
  value = aws_instance.elk_client.public_ip
}
