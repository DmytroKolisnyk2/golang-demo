#!/bin/bash
# Update and install dependencies
sudo apt update -y
sudo apt install -y nginx git postgresql postgresql-contrib
sudo snap install go --classic

# Start and enable Nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# Install and configure PostgreSQL locally 
sudo service postgresql start
sudo systemctl enable postgresql

# Set environment variables from Terraform 
DB_ENDPOINT="${db_endpoint}"
DB_USER="${db_user}"
DB_PASS="${db_password}"
DB_NAME="${db_name}"
DB_PORT=5432
GIN_MODE=release


# Clone the Golang demo application
cd /home/ubuntu
git clone https://github.com/DmytroKolisnyk2/golang-demo.git
cd golang-demo

# Apply schema to the new remote database
PGPASSWORD=$DB_PASS psql -h $DB_ENDPOINT -U $DB_USER -p $DB_PORT -d $DB_NAME -f db_schema.sql

# Build the Golang binary
sudo GOOS=linux GOARCH=amd64 go build -o golang-demo -buildvcs=false
sudo chmod +x golang-demo

# Start the Golang application with the required environment variables
sudo DB_ENDPOINT=$DB_ENDPOINT DB_PORT=$DB_PORT DB_USER=$DB_USER DB_PASS=$DB_PASS DB_NAME=$DB_NAME ./golang-demo 

# Configure Nginx to proxy traffic to the Golang application
sudo bash -c 'cat > /etc/nginx/sites-available/default' << EOF
server {
    listen 80;
    server_name localhost;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Restart Nginx to apply the new configuration
sudo systemctl restart nginx
