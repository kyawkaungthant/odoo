#!/bin/bash

# Define text styles
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BOLD="\e[1m"
BLUE="\e[34m"
RESET="\e[0m"
CHECK_MARK="\u2714"  # Checkmark symbol
CROSS_MARK="\u2718"  # Cross symbol

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
    echo -e "${GREEN}${CHECK_MARK} UAT server is now running on ${BLUE}${BOLD}http://${PUBLIC_IP}:8069${RESET}"
else
    echo -e "${RED}${BOLD}${CROSS_MARK} UAT server setup failed. Please check for errors.${RESET}"
fi

# Check Production server status
if check_server_status 8070; then
    echo -e "${GREEN}${CHECK_MARK} Production server is now running on ${BLUE}${BOLD}http://${PUBLIC_IP}:8070${RESET}"
else
    echo -e "${RED}${BOLD}${CROSS_MARK} Production server setup failed. Please check for errors.${RESET}"
fi
