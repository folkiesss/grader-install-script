#!/bin/bash
# Cafe Grader Automated Installation Script
# This script automates the installation of Cafe Grader system

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_prompt() {
    echo -e "${BLUE}[PROMPT]${NC} $1"
}

# Banner
echo "==================================================="
echo "     Cafe Grader Installation Script"
echo "==================================================="
echo ""

# Prompt for database configuration
log_info "Database Configuration Setup"
echo ""

# Database name
log_prompt "Enter the main database name (default: grader):"
read -p "Database name: " DB_NAME
DB_NAME=${DB_NAME:-grader}

# Database queue name
log_prompt "Enter the queue database name (default: grader_queue):"
read -p "Queue database name: " DB_QUEUE_NAME
DB_QUEUE_NAME=${DB_QUEUE_NAME:-grader_queue}

# Database user
log_prompt "Enter the database username (default: grader_user):"
read -p "Database username: " DB_USER
DB_USER=${DB_USER:-grader_user}

# Database password (hidden input)
while true; do
    log_prompt "Enter the database password (default: grader_pass):"
    read -s -p "Database password: " DB_PASS
    echo ""
    
    if [ -z "$DB_PASS" ]; then
        DB_PASS="grader_pass"
        break
    fi
    
    read -s -p "Confirm password: " DB_PASS_CONFIRM
    echo ""
    
    if [ "$DB_PASS" = "$DB_PASS_CONFIRM" ]; then
        break
    else
        log_error "Passwords do not match. Please try again."
    fi
done

# Linux user
LINUX_USER=$(whoami)
log_prompt "Installation will run as user: $LINUX_USER"
read -p "Press Enter to continue or Ctrl+C to abort..."

# Installation directory
INSTALL_DIR="$HOME/cafe_grader"
log_prompt "Installation directory (default: $INSTALL_DIR):"
read -p "Installation directory: " CUSTOM_DIR
if [ ! -z "$CUSTOM_DIR" ]; then
    INSTALL_DIR="$CUSTOM_DIR"
fi

# Number of grader workers
log_prompt "Number of grader workers (default: 4):"
read -p "Workers: " NUM_WORKERS
NUM_WORKERS=${NUM_WORKERS:-4}

# Port configuration
log_prompt "Web server port (default: 3000):"
read -p "Port: " WEB_PORT
WEB_PORT=${WEB_PORT:-3000}

echo ""
log_info "Configuration Summary:"
echo "  Database Name:       $DB_NAME"
echo "  Queue Database:      $DB_QUEUE_NAME"
echo "  Database User:       $DB_USER"
echo "  Database Password:   [hidden]"
echo "  Linux User:          $LINUX_USER"
echo "  Install Directory:   $INSTALL_DIR"
echo "  Grader Workers:      $NUM_WORKERS"
echo "  Web Port:            $WEB_PORT"
echo ""
read -p "Continue with installation? (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    log_error "Installation aborted by user"
    exit 1
fi

log_info "Starting Cafe Grader installation..."

# 1. Update system packages
log_info "Step 1: Updating system packages..."
sudo apt update && sudo apt upgrade -y

# 2. Install required packages
log_info "Step 2: Installing required packages..."
sudo apt install -y \
    apache2 \
    apache2-dev \
    mysql-server \
    git \
    software-properties-common \
    libmysqlclient-dev \
    libcap-dev \
    apt-transport-https \
    postgresql \
    postgresql-server-dev-all \
    unzip \
    curl \
    libsystemd-dev

# 3. Install Node.js
log_info "Step 3: Installing Node.js..."
curl -sL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh
sudo bash /tmp/nodesource_setup.sh
sudo apt install -y nodejs

# 4. Install RVM
log_info "Step 4: Installing RVM..."
sudo apt-add-repository -y ppa:rael-gc/rvm
sudo apt update
sudo apt install -y rvm
sudo usermod -a -G rvm $LINUX_USER

log_warn "RVM group added. You may need to log out and log back in for group changes to take effect."

# Source RVM
if [ -f /etc/profile.d/rvm.sh ]; then
    source /etc/profile.d/rvm.sh
fi

# 5. Setup MySQL databases
log_info "Step 5: Setting up MySQL databases..."
log_info "Creating database '$DB_NAME' and '$DB_QUEUE_NAME'..."
sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE DATABASE IF NOT EXISTS $DB_QUEUE_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON $DB_QUEUE_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

log_info "MySQL databases created successfully"

# 6. Install IOI/Isolate
log_info "Step 6: Installing IOI/Isolate..."
cd $HOME
if [ ! -d "isolate" ]; then
    git clone https://github.com/ioi/isolate.git
fi
cd isolate
make isolate
sudo make install
log_info "IOI/Isolate installed"

# 7. Host configuration for isolate
log_info "Step 7: Configuring host for isolate..."

# Turn off swap
log_info "Disabling swap..."
sudo swapoff -a

# Create systemd service link
sudo ln -sf $HOME/isolate/systemd/isolate.service /etc/systemd/system/

# Create set-ioi-isolate.service
log_info "Creating set-ioi-isolate.service..."
sudo tee /etc/systemd/system/set-ioi-isolate.service > /dev/null <<'EOF'
[Unit]
Description=Set Transparent Hugepage and Core Pattern Settings for IOI isolate
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/enabled; \
                      echo never > /sys/kernel/mm/transparent_hugepage/defrag; \
                      echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/defrag; \
                      echo core > /proc/sys/kernel/core_pattern;"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload
sudo systemctl enable set-ioi-isolate.service
sudo systemctl enable isolate.service

# Disable address space randomization
log_info "Disabling address space randomization..."
echo 'kernel.randomize_va_space=0' | sudo tee /etc/sysctl.d/99-sysctl.conf > /dev/null

# Configure GRUB
log_info "Configuring GRUB for cgroup memory..."
if [ -f /etc/default/grub ]; then
    if ! grep -q "cgroup_enable=memory" /etc/default/grub; then
        sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& cgroup_enable=memory/' /etc/default/grub
        sudo update-grub
        log_warn "GRUB updated. System reboot required after installation completes."
    fi
else
    log_warn "GRUB configuration file not found (/etc/default/grub). Skipping GRUB configuration."
    log_warn "You may need to manually configure cgroup_enable=memory in your bootloader."
fi

# 8. Clone Cafe Grader
log_info "Step 8: Cloning Cafe Grader repository..."
mkdir -p "$INSTALL_DIR"
if [ ! -d "$INSTALL_DIR/web" ]; then
    git clone https://github.com/nattee/cafe-grader-web.git "$INSTALL_DIR/web"
else
    log_warn "Cafe Grader web directory already exists, skipping clone"
fi

cd "$INSTALL_DIR/web"

# 9. Install Ruby
log_info "Step 9: Installing Ruby..."
if [ -f .ruby-version ]; then
    RUBY_VERSION=$(cat .ruby-version | tr -d '[:space:]')
    log_info "Installing Ruby ${RUBY_VERSION}..."
    
    # Source RVM if available
    if [ -f /etc/profile.d/rvm.sh ]; then
        source /etc/profile.d/rvm.sh
        rvm install ${RUBY_VERSION}
        rvm use ${RUBY_VERSION}
    else
        log_error "RVM not properly sourced. Please log out and log back in, then run this script again."
        exit 1
    fi
else
    log_error ".ruby-version file not found"
    exit 1
fi

# 10. Bundle install
log_info "Step 10: Running bundle install..."
gem install bundler
bundle install

# 11. Copy and configure config files
log_info "Step 11: Configuring application..."

# Copy config files
cp config/application.rb.SAMPLE config/application.rb
cp config/database.yml.SAMPLE config/database.yml
cp config/worker.yml.SAMPLE config/worker.yml

# Configure database.yml
log_info "Configuring database.yml..."
cat > config/database.yml <<EOF
user_pass: &user_pass
  username: $DB_USER
  password: $DB_PASS

default: &default
  adapter: mysql2
  encoding: utf8mb4
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: localhost
  socket: /var/run/mysqld/mysqld.sock

test:
  <<: [*user_pass]
  adapter: mysql2
  database: grader_test

production:
  primary:
    <<: [*user_pass, *default]
    database: $DB_NAME
  queue:
    <<: [*user_pass, *default]
    database: $DB_QUEUE_NAME
    migrations_paths: db/queue_migrate

development:
  primary:
    <<: [*user_pass, *default]
    database: $DB_NAME
  queue:
    <<: [*user_pass, *default]
    database: $DB_QUEUE_NAME
    migrations_paths: db/queue_migrate
EOF

# Configure worker.yml
log_info "Configuring worker.yml..."
cat > config/worker.yml <<EOF
shared:
  directory:
    isolate_working_dir: /var/local/lib/isolate/
    judge_path: <%= ENV['HOME'] %>/cafe_grader/judge
    judge_raw_path: <%= Rails.root.join('..', 'judge','raw').cleanpath %>
    judge_log_file: <%= Rails.root.join 'log','judge' %>
    grader_stdout_base_file: <%= Rails.root.join 'log','grader-' %>
  compiler:
    cpp: /usr/bin/g++
    c: <%= \`which gcc\`.strip %>
    ruby: <%= \`which ruby\`.strip %>
    python: <%= \`which python3\`.strip %>
    javac: <%= \`which javac\`.strip %>
    java: <%= \`which java\`.strip %>
    digital: <%= Rails.root.join 'lib','language', 'digital','Digital.jar' %>
    haskell: <%= \`which ghc\`.strip %>
    rust: <%= \`which rustc\`.strip %>
    go: <%= \`which go\`.strip %>
    pas: <%= \`which fpc\`.strip %>
  isolate_path: <%= \`which isolate\`.strip %>
  hosts:
    web: http://localhost:$WEB_PORT

development:
  server_key: c2f7966dee
  worker_id: 1
  worker_passcode: aa0429lljka429ukljh3904i2ljk1kj

production:
  server_key: c2f7966dee
  worker_id: 1
  worker_passcode: aa0429lljka429ukljh3904i2ljk1kj
EOF

# 12. Setup Rails
log_info "Step 12: Setting up Rails..."

# Setup credentials
log_warn "You need to setup Rails credentials manually..."
log_warn "The editor will open. Just save and close it (Ctrl+X, then Y, then Enter if using nano)"
read -p "Press Enter to continue..."
EDITOR=nano rails credentials:edit

# Setup database
log_info "Setting up database schema..."
rails db:setup DISABLE_DATABASE_ENVIRONMENT_CHECK=1 RAILS_ENV=production
rails db:seed RAILS_ENV=production

# Setup yarn
log_info "Setting up Yarn..."
sudo corepack enable
corepack prepare yarn@stable --activate
yarn install

# Precompile assets
log_info "Precompiling assets..."
rails assets:precompile RAILS_ENV=production

# 13. Setup Solid Queue service
log_info "Step 13: Setting up Solid Queue service..."
sudo tee /etc/systemd/system/solid_queue.service > /dev/null <<EOF
[Unit]
Description=Solid Queue for cafe-grader
After=network.target

[Service]
User=$LINUX_USER
WorkingDirectory=$INSTALL_DIR/web
ExecStart=/bin/bash -lc 'bundle exec rails solid_queue:start'
Environment=RAILS_ENV=production
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable solid_queue

# 14. Setup grader process and cron jobs
log_info "Step 14: Setting up grader process and cron jobs..."
cd "$INSTALL_DIR/web"
RAILS_ENV=production rails r "Grader.restart($NUM_WORKERS)"
bundle exec whenever --update-crontab

# Add cleanup cron job
(crontab -l 2>/dev/null; echo "0 2 * * * find $INSTALL_DIR/judge/isolate_submission/ -maxdepth 1 -mtime +1 -exec rm -rf {} \\;") | crontab -

# 15. Save configuration to file
log_info "Saving configuration..."
cat > "$INSTALL_DIR/installation_config.txt" <<EOF
Cafe Grader Installation Configuration
=======================================
Installation Date: $(date)
Installation User: $LINUX_USER
Installation Directory: $INSTALL_DIR

Database Configuration:
- Main Database: $DB_NAME
- Queue Database: $DB_QUEUE_NAME
- Database User: $DB_USER
- Database Password: $DB_PASS

Application Configuration:
- Grader Workers: $NUM_WORKERS
- Web Port: $WEB_PORT
- Web URL: http://localhost:$WEB_PORT

MySQL Socket: /var/run/mysqld/mysqld.sock
Isolate Directory: /var/local/lib/isolate/

Post-Installation Commands:
1. Reboot system: sudo reboot
2. Start Solid Queue: sudo systemctl start solid_queue
3. Start Rails Server: cd $INSTALL_DIR/web && RAILS_ENV=production rails server -b 0.0.0.0 -p $WEB_PORT -d
4. Check status: sudo systemctl status solid_queue
EOF

chmod 600 "$INSTALL_DIR/installation_config.txt"

# 16. Create helper scripts
log_info "Creating helper scripts..."

# Start script
cat > "$INSTALL_DIR/start_grader.sh" <<EOF
#!/bin/bash
cd $INSTALL_DIR/web
sudo systemctl start solid_queue
RAILS_ENV=production rails server -b 0.0.0.0 -p $WEB_PORT -d
echo "Cafe Grader started on http://localhost:$WEB_PORT"
EOF
chmod +x "$INSTALL_DIR/start_grader.sh"

# Stop script
cat > "$INSTALL_DIR/stop_grader.sh" <<EOF
#!/bin/bash
sudo systemctl stop solid_queue
pkill -f "rails server"
echo "Cafe Grader stopped"
EOF
chmod +x "$INSTALL_DIR/stop_grader.sh"

# Status script
cat > "$INSTALL_DIR/status_grader.sh" <<EOF
#!/bin/bash
echo "=== Solid Queue Status ==="
sudo systemctl status solid_queue
echo ""
echo "=== Rails Server Status ==="
ps aux | grep "rails server" | grep -v grep
EOF
chmod +x "$INSTALL_DIR/status_grader.sh"

# Final completion message
log_info "Installation completed successfully!"
echo ""
echo "==================================================="
echo "     Cafe Grader Installation Complete!"
echo "==================================================="
echo ""
log_info "Configuration Details:"
echo "  Database:        $DB_NAME / $DB_QUEUE_NAME"
echo "  Database User:   $DB_USER"
echo "  Install Dir:     $INSTALL_DIR"
echo "  Workers:         $NUM_WORKERS"
echo "  Web Port:        $WEB_PORT"
echo ""
log_warn "IMPORTANT: Next Steps"
echo ""
echo "1. REBOOT your system (required for kernel changes):"
echo "   ${GREEN}sudo reboot${NC}"
echo ""
echo "2. After reboot, start Cafe Grader:"
echo "   ${GREEN}$INSTALL_DIR/start_grader.sh${NC}"
echo "   OR manually:"
echo "   ${GREEN}cd $INSTALL_DIR/web${NC}"
echo "   ${GREEN}sudo systemctl start solid_queue${NC}"
echo "   ${GREEN}RAILS_ENV=production rails server -b 0.0.0.0 -p $WEB_PORT -d${NC}"
echo ""
echo "3. Access the application:"
echo "   ${BLUE}http://localhost:$WEB_PORT${NC}"
echo ""
log_info "Helper Scripts Created:"
echo "  Start:  $INSTALL_DIR/start_grader.sh"
echo "  Stop:   $INSTALL_DIR/stop_grader.sh"
echo "  Status: $INSTALL_DIR/status_grader.sh"
echo ""
log_info "Configuration saved to:"
echo "  $INSTALL_DIR/installation_config.txt"
echo ""
echo "==================================================="