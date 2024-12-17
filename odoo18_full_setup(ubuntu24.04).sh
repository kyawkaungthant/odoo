#!/bin/bash

# Define text styles
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BOLD="\e[1m"
BLUE="\e[34m"
RESET="\e[0m"
CHECK_MARK="\u2714"
CROSS_MARK="\u2718"

# Check if the enterprise-18.0 directory already exists under /opt/odoo/
if ! sudo [ -d "/opt/odoo/enterprise-18.0" ]; then
    # If the directory does not exist, check if enterprise-18.0.zip exists in the same directory as the script
    if [ ! -f "enterprise-18.0.zip" ]; then
        echo -e "${RED}Error: The file 'enterprise-18.0.zip' is missing.${RESET}"
        echo -e "${RED}Please place the 'enterprise-18.0.zip' file in the same directory as this script and try again.${RESET}"
        exit 1
    fi
fi

# Update and upgrade packages
sudo apt-get update -y && sudo apt-get upgrade -y

# Install required dependencies
sudo apt install -y git unzip python3-pip build-essential wget python3-dev python3-venv \
    python3-wheel libxml2-dev libzip-dev libldap2-dev libsasl2-dev \
    python3-setuptools node-less libjpeg-dev zlib1g-dev libpq-dev \
    libxslt1-dev libtiff5-dev libjpeg8-dev libopenjp2-7-dev \
    liblcms2-dev libwebp-dev libharfbuzz-dev libfribidi-dev libxcb1-dev \
    libssl-dev libffi-dev libmysqlclient-dev libblas-dev libatlas-base-dev \
    libcairo2-dev pkg-config

# Check if the Odoo user exists before creating it
if id "odoo" &>/dev/null; then
    echo -e "${YELLOW}User 'odoo' already exists.${RESET}"
else
    sudo useradd -m -d /opt/odoo -U -r -s /bin/bash odoo
    echo "User 'odoo' created."
fi

# Install PostgreSQL if it's not installed
if ! dpkg -l | grep -q postgresql; then
    sudo apt install postgresql -y
else
    echo -e "${YELLOW}PostgreSQL is already installed.${RESET}"
fi

# Check if the Odoo user exists in PostgreSQL
if sudo su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='odoo'\"" | grep -q 1; then
    echo -e "${YELLOW}Postgres user 'odoo' already exists.${RESET}"
else
    sudo su - postgres -c "createuser -s odoo"
    echo "Postgres user 'odoo' created."
fi

# Add focal-security repository
echo "deb http://security.ubuntu.com/ubuntu focal-security main" | sudo tee /etc/apt/sources.list.d/focal-security.list

# Install other necessary packages
sudo apt install xfonts-75dpi xfonts-base -y
sudo apt-get update
sudo apt-get install libssl1.1 -y
sudo apt --fix-broken install -y

# Check if wkhtmltox_0.12.5-1.bionic_amd64.deb already exists
if [ ! -f "wkhtmltox_0.12.5-1.bionic_amd64.deb" ]; then
    # Download wkhtmltopdf if it's not already installed
    if ! wkhtmltopdf --version 2>/dev/null | grep -q "wkhtmltopdf 0.12.5"; then
        sudo wget https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb
        sudo apt install -y ./wkhtmltox_0.12.5-1.bionic_amd64.deb
    else
        echo -e "${YELLOW}wkhtmltopdf is already installed.${RESET}"
    fi
else
    echo -e "${YELLOW}File wkhtmltox_0.12.5-1.bionic_amd64.deb already exists. Skipping download.${RESET}"
fi

# Install npm and related packages
sudo apt install -y npm
sudo ln -sf /usr/bin/nodejs /usr/bin/node  # Use -sf to force overwrite of existing symlink
sudo npm install -g less less-plugin-clean-css
sudo apt-get install -y node-less

# Move enterprise zip to Odoo directory only if it doesn't already exist there
if ! sudo [ -d "/opt/odoo/enterprise-18.0" ]; then
    sudo mv enterprise-18.0.zip /opt/odoo/
    sudo su - odoo << EOF
    unzip /opt/odoo/enterprise-18.0.zip
EOF
else
    echo -e "${YELLOW}Enterprise folder already exists in /opt/odoo.${RESET}"
fi

# Check if the odoo repository is already cloned
sudo su - odoo << EOF
# Check if the odoo repository already exists
if [ ! -d "odoo" ]; then
    git clone --depth 1 --branch 18.0 https://github.com/odoo/odoo.git
else
    echo -e "${YELLOW}Directory 'odoo' already exists. Skipping clone.${RESET}"
fi

# Check if the design-themes repository already exists
if [ ! -d "design-themes" ]; then
    git clone --depth 1 --branch 18.0 https://github.com/odoo/design-themes.git
else
    echo -e "${YELLOW}Directory 'design-themes' already exists. Skipping clone.${RESET}"
fi
EOF

# Create virtual environment and install Python requirements
sudo su - odoo << EOF
# Create virtual environment if it does not exist
if [ ! -d "odoo-venv" ]; then
    python3 -m venv odoo-venv
    echo "Virtual environment created."
fi

# Activate the virtual environment and install requirements
source /opt/odoo/odoo-venv/bin/activate
pip3 install --upgrade pip  # Upgrade pip to the latest version
pip3 install wheel
pip3 install -r /opt/odoo/odoo/requirements.txt
deactivate
pip3 install -r /opt/odoo/odoo/requirements.txt
EOF

# Create UAT configuration file if it doesn't exist
if [ ! -f "/etc/odoo.conf" ]; then
    sudo tee /etc/odoo.conf > /dev/null <<EOL
[options]
admin_passwd = Ztt@!2024
db_host = False
db_port = False
db_user = odoo
db_password = False
#dbfilter = ^db$
addons_path = /opt/odoo/enterprise-18.0, /opt/odoo/odoo/addons, /opt/odoo/design-themes
proxy_mode = True
http_port = 8069
https_port = 443
logfile = /var/log/odoo/odoo.log
logrotate = True
log_level = info
log_handler=werkzeug:WARNING,odoo:INFO
log_db = True
log_db_level = info

; Server port
xmlrpc_port = 8069
EOL
else
    echo -e "${YELLOW}UAT configuration file already exists.${RESET}"
fi

# Create Prod configuration file if it doesn't exist
if [ ! -f "/etc/odoo_prod.conf" ]; then
    sudo tee /etc/odoo_prod.conf > /dev/null <<EOL
[options]
admin_passwd = Ztt@!2024
db_host = False
db_port = False
db_user = odoo
db_password = False
#dbfilter = ^db$
addons_path = /opt/odoo/enterprise-18.0, /opt/odoo/odoo/addons, /opt/odoo/design-themes
proxy_mode = True
http_port = 8070
https_port = 443
logfile = /var/log/odoo/odoo_prod.log
logrotate = True
log_level = warn
log_handler=werkzeug:CRITICAL,odoo:ERROR
log_db = True
log_db_level = warning

; Server port
xmlrpc_port = 8070
EOL
else
    echo -e "${YELLOW}Production configuration file already exists.${RESET}"
fi

# Configure systemd service for UAT if it doesn't exist
if [ ! -f "/etc/systemd/system/odoo.service" ]; then
    sudo tee /etc/systemd/system/odoo.service > /dev/null <<EOL
[Unit]
Description=odoo
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo
PermissionsStartOnly=true
User=odoo
Group=odoo
ExecStart=/opt/odoo/odoo-venv/bin/python3 /opt/odoo/odoo/odoo-bin -c /etc/odoo.conf
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOL
else
    echo -e "${YELLOW}UAT service file already exists.${RESET}"
fi

# Configure systemd service for Prod if it doesn't exist
if [ ! -f "/etc/systemd/system/odoo_prod.service" ]; then
    sudo tee /etc/systemd/system/odoo_prod.service > /dev/null <<EOL
[Unit]
Description=odoo_prod
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo
PermissionsStartOnly=true
User=odoo
Group=odoo
ExecStart=/opt/odoo/odoo-venv/bin/python3 /opt/odoo/odoo/odoo-bin -c /etc/odoo_prod.conf
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOL
else
    echo -e "${YELLOW}Production service file already exists.${RESET}"
fi

# Reload systemd and restart Odoo services
sudo systemctl daemon-reload
sudo systemctl enable --now odoo
sudo systemctl enable --now odoo_prod

# Ensure the log directory exists and set permissions
sudo mkdir -p /var/log/odoo/
sudo chown -R odoo:odoo /var/log/odoo/
sudo systemctl restart odoo
sudo systemctl restart odoo_prod

echo -e "${GREEN}${BOLD}Odoo UAT and Production setup is completed!${RESET}"

# Get public IP using an external service
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com/)

# Function to check server status with retries
check_server_status() {
    local port=$1
    local retries=6  # Number of retries
    local delay=10    # Delay in seconds between retries

    for ((i=1; i<=retries; i++)); do
        if curl -s --head http://localhost:${port} | grep -q "HTTP/[0-9]\+\(\.[0-9]\+\)\? 303"; then
            return 0  # Success
        fi
        echo "Checking servers status..."
        sleep ${delay}  # Wait before the next attempt
    done
    return 1  # Failure after retries
}

# Check UAT server status
if check_server_status 8069; then
    echo -e "${GREEN}${BOLD}${CHECK_MARK} UAT server is now running on ${BLUE}http://${PUBLIC_IP}:8069${RESET}"
else
    echo -e "${RED}${BOLD}${CROSS_MARK} UAT server setup failed. Please check for errors.${RESET}"
fi

# Check Production server status
if check_server_status 8070; then
    echo -e "${GREEN}${BOLD}${CHECK_MARK} Production server is now running on ${BLUE}http://${PUBLIC_IP}:8070${RESET}"
else
    echo -e "${RED}${BOLD}${CROSS_MARK} Production server setup failed. Please check for errors.${RESET}"
fi

# Set the timezone to Asia/Yangon
sudo timedatectl set-timezone Asia/Yangon

echo "Configuring systemd journal log retention settings..."

# Define an associative array with the settings to update
declare -A settings=(
    ["SystemMaxUse"]="500M"
    ["SystemKeepFree"]="5G"
    ["SystemMaxFileSize"]="50M"
    ["SystemMaxFiles"]="10"
    ["MaxRetentionSec"]="1month"
)

# Read the original file into an array
mapfile -t lines < /etc/systemd/journald.conf

# Track which settings have been processed
declare -A processed=(
    ["SystemMaxUse"]=false
    ["SystemKeepFree"]=false
    ["SystemMaxFileSize"]=false
    ["SystemMaxFiles"]=false
    ["MaxRetentionSec"]=false
)

# Update the configuration in memory
for i in "${!lines[@]}"; do
    line="${lines[i]}"

    for key in "${!settings[@]}"; do
        # Check for uncommented variables and update them if they exist
        if [[ "$line" == "$key="* ]]; then
            lines[i]="$key=${settings[$key]}"
            processed[$key]=true
        fi
    done
done

# Process commented variables if uncommented ones are not found
for i in "${!lines[@]}"; do
    line="${lines[i]}"

    for key in "${!settings[@]}"; do
        if [[ "$line" == \#$key=* && ${processed[$key]} == false ]]; then
            lines[i]="${key}=${settings[$key]}"  # Uncomment and replace
            processed[$key]=true
        fi
    done
done

# Append any settings that were not found in the array
for key in "${!settings[@]}"; do
    if ! grep -q "^$key=" /etc/systemd/journald.conf && ! grep -q "^#$key=" /etc/systemd/journald.conf; then
        lines+=("$key=${settings[$key]}")
    fi
done

# Write the updated array back to the configuration file
printf "%s\n" "${lines[@]}" | sudo tee /etc/systemd/journald.conf > /dev/null

echo "Journal log configuration updated."

# Apply changes and restart systemd-journald
sudo systemctl restart systemd-journald

echo "Configuring PostgreSQL logging..."

# Get the PostgreSQL version (assumes only one version installed)
version=$(ls /etc/postgresql | grep -E '^[0-9]+')

# Define the logging options
logging_collector="logging_collector = on"
log_directory="log_directory = '/var/log/postgresql'"
log_filename="log_filename = 'postgresql-%Y-%m-%d.log'"
log_min_messages="log_min_messages = warning"
log_min_error_statement="log_min_error_statement = error"
log_statement="log_statement = 'mod'"
log_timezone="log_timezone = 'Asia/Yangon'"

# Update or add each logging configuration
for config_line in "$logging_collector" "$log_directory" "$log_filename" "$log_min_messages" "$log_min_error_statement" "$log_statement" "$log_timezone"; do
    config_key=$(echo "$config_line" | cut -d' ' -f1)
    if grep -q "^$config_key[[:space:]]*=" /etc/postgresql/$version/main/postgresql.conf; then
        sudo sed -i "s|^$config_key[[:space:]]*=.*|$config_line|" /etc/postgresql/$version/main/postgresql.conf
    elif grep -q "^#$config_key[[:space:]]*=" /etc/postgresql/$version/main/postgresql.conf; then
        sudo sed -i "s|^#$config_key[[:space:]]*=.*|$config_line|" /etc/postgresql/$version/main/postgresql.conf
    else
        echo "$config_line" | sudo tee -a /etc/postgresql/$version/main/postgresql.conf > /dev/null
    fi
done

echo "PostgreSQL log configuration updated."

# Restart PostgreSQL to apply changes
sudo systemctl restart postgresql

echo "Setting up PostgreSQL log rotation..."

# Overwrite the logrotate config for PostgreSQL logs
sudo tee /etc/logrotate.d/postgresql-common > /dev/null <<EOL
/var/log/postgresql/*.log {
    daily
    rotate 7
    copytruncate
    notifempty
    missingok
    su root root
}
EOL

echo "PostgreSQL log rotation configured."

echo "Setting up Odoo log rotation..."

# Overwrite the logrotate config for Odoo logs
sudo tee /etc/logrotate.d/odoo > /dev/null <<EOL
/var/log/odoo/*.log {
    daily
    rotate 7
    missingok
    notifempty
    dateext
    dateformat -%Y-%m-%d
    copytruncate
}
EOL

echo "Odoo log rotation configured."

# Check if Nginx is already installed
if ! dpkg -l | grep -q nginx; then
    # Install Nginx
    echo -e "Installing Nginx..."
    sudo apt update
    sudo apt install -y nginx

    # Start Nginx service and enable it to start on boot
    echo -e "Starting and enabling Nginx..."
    sudo systemctl start nginx
    sudo systemctl enable nginx
else
    echo -e "${YELLOW}Nginx is already installed.${RESET}"
fi

# Function to validate domain input
validate_domain() {
    local domain=$1
    # If the input is not empty and does not end with ".com"
    if [[ -n "$domain" && ! "$domain" =~ \.com$ ]]; then
        return 1  # Invalid domain
    fi
    return 0  # Valid domain or skipped
}

# Function to prompt for a domain with validation
ask_for_domain() {
    local domain_var=$1
    local domain_value=""

    while true; do
        read -p "Please add domain name for ${domain_var} (Press Enter to skip): " domain_value
        
        # No domain entered, skip this
        if [[ -z "$domain_value" ]]; then
            echo -e "${YELLOW}No domain entered. Proceeding without it.${RESET}" >&2
            echo "_"  # Return underscore to indicate skip
            return
        fi
        
        # Validate the domain
        if ! validate_domain "$domain_value"; then
            # Output the error message to stderr
            echo -e "${RED}Invalid domain name. Please enter a valid domain name that ends with '.com'.${RESET}" >&2
        else
            echo "$domain_value"  # Return the valid domain
            return
        fi
    done
}

# Ask for UAT domain input
UAT_DOMAIN=$(ask_for_domain "UAT")

# Ask for Prod domain input
PROD_DOMAIN=$(ask_for_domain "Production")

# UAT Nginx configuration (directly under sites-enabled)
sudo tee /etc/nginx/sites-enabled/odoo_uat > /dev/null <<EOL
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

server {
    listen 80;
    server_name ${UAT_DOMAIN};

    # Redirect requests to Odoo UAT backend
    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_redirect off;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    }

    # Redirect longpolling requests for UAT
    location /longpolling {
        proxy_pass http://127.0.0.1:8072;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    }

    # Log
    access_log /var/log/nginx/odoo_uat.access.log;
    error_log /var/log/nginx/odoo_uat.error.log;

    # Additional configurations
    client_max_body_size 8G;
    proxy_max_temp_file_size 8192M;
    proxy_read_timeout 1800s;
    proxy_connect_timeout 1800s;
    proxy_send_timeout 1800s;

    # Gzip configuration
    gzip on;
    gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript;
    gzip_min_length 1000;
    gzip_proxied expired no-cache no-store private auth;
}
EOL

# Prod Nginx configuration (directly under sites-enabled)
sudo tee /etc/nginx/sites-enabled/odoo_prod > /dev/null <<EOL
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

server {
    listen 80;
    server_name ${PROD_DOMAIN};

    # Redirect requests to Odoo Prod backend
    location / {
        proxy_pass http://127.0.0.1:8070;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_redirect off;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    }

    # Redirect longpolling requests for Prod
    location /longpolling {
        proxy_pass http://127.0.0.1:8073;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    }

    # Log
    access_log /var/log/nginx/odoo_prod.access.log;
    error_log /var/log/nginx/odoo_prod.error.log;

    # Additional configurations
    client_max_body_size 8G;
    proxy_max_temp_file_size 8192M;
    proxy_read_timeout 1800s;
    proxy_connect_timeout 1800s;
    proxy_send_timeout 1800s;

    # Gzip configuration
    gzip on;
    gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript;
    gzip_min_length 1000;
    gzip_proxied expired no-cache no-store private auth;
}
EOL

# Adding longpolling port
echo "Adding longpolling port..."

# Check and append to /etc/odoo.conf if not present
if ! grep -q "longpolling_port = 8072" /etc/odoo.conf; then
    echo "Appending longpolling configuration to /etc/odoo.conf..."
    sudo tee -a /etc/odoo.conf > /dev/null <<EOL

; Worker Configuration
#workers = 1
#max_cron_threads = 1

; Memory and Limit Settings
#limit_memory_hard =
#limit_memory_soft =
#limit_request = 4098
limit_time_cpu = 900
limit_time_real = 1800

; Longpolling Configuration
longpolling_port = 8072
EOL
else
    echo "/etc/odoo.conf already contains longpolling configuration."
fi

# Check and append to /etc/odoo_prod.conf if not present
if ! grep -q "longpolling_port = 8073" /etc/odoo_prod.conf; then
    echo "Appending longpolling configuration to /etc/odoo_prod.conf..."
    sudo tee -a /etc/odoo_prod.conf > /dev/null <<EOL

; Worker Configuration
#workers = 2
#max_cron_threads = 1

; Memory and Limit Settings
#limit_memory_hard =
#limit_memory_soft =
#limit_request = 8196
limit_time_cpu = 900
limit_time_real = 1800

; Longpolling Configuration
longpolling_port = 8073
EOL
else
    echo "/etc/odoo_prod.conf already contains longpolling configuration."
fi

echo "Longpolling port configuration completed."

# Test Nginx configuration for syntax errors
if sudo nginx -t; then
    # Restart Nginx to apply the changes
    sudo systemctl restart nginx
    echo -e "${GREEN}${BOLD}Nginx configuration for UAT and Prod is complete!${RESET}"

    # Check if any domain was provided to install and configure Certbot
    if [[ "$UAT_DOMAIN" != "_" || "$PROD_DOMAIN" != "_" ]]; then
        echo -e "${BOLD}A domain was provided. Installing Certbot for SSL...${RESET}"

        # Install Certbot and configure SSL
        sudo snap install --classic certbot
        sudo ln -s /snap/bin/certbot /usr/bin/certbot

        # Run Certbot (it will automatically detect the domain from Nginx configs)
        if ! sudo certbot --nginx; then
            echo -e "${RED}${BOLD}SSL certificate installation failed. Please check if your domain exists and redirects to this instance's IP address.${RESET}"
            exit 1  # Exit the script with a non-zero status to indicate failure
        fi

        # Setup automatic renewal for Certbot
        sudo certbot renew --dry-run
        echo -e "${GREEN}${BOLD}SSL certificate installation and renewal setup complete!${RESET}"
    else
        echo -e "${YELLOW}No domain provided, skipping Certbot installation.${RESET}"
    fi
else
    echo -e "${RED}${BOLD}Nginx configuration failed. Please check for errors.${RESET}"
fi

# Function to check server status with retries
check_server_status() {
    local domain=$1  # The domain name passed as an argument
    local retries=3   # Number of retries
    local delay=8     # Delay in seconds between retries

    for ((i=1; i<=retries; i++)); do
        # Check if the HTTP response
        if curl -s --head "https://$domain" | grep -q "HTTP/[0-9]\+\(\.[0-9]\+\)\? 303"; then
            return 0  # Success
        fi
        echo "Checking status for $domain..."
        sleep ${delay}  # Wait before the next attempt
    done
    return 1  # Failure after retries
}


# Check UAT server status
if [[ "$UAT_DOMAIN" != "_" ]]; then  # Check if UAT_DOMAIN is not empty
    if check_server_status "$UAT_DOMAIN"; then  # Pass UAT_DOMAIN to the function
        echo -e "${GREEN}${BOLD}${CHECK_MARK} UAT server is now running on ${BLUE}https://$UAT_DOMAIN${RESET}"
    else
        echo -e "${RED}${BOLD}${CROSS_MARK}Domain name setup for UAT server failed. Please check for errors.${RESET}"
    fi
fi

# Check Production server status
if [[ "$PROD_DOMAIN" != "_" ]]; then  # Check if PROD_DOMAIN is not empty
    if check_server_status "$PROD_DOMAIN"; then  # Pass PROD_DOMAIN to the function
        echo -e "${GREEN}${BOLD}${CHECK_MARK} Production server is now running on ${BLUE}https://$PROD_DOMAIN${RESET}"
    else
        echo -e "${RED}${BOLD}${CROSS_MARK}Domain name setup for Production server failed. Please check for errors.${RESET}"
    fi
fi
