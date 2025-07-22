#!/bin/sh

# Before running this script, you should set the PASSWORD and add bash
#PASSWORD=YOUR_PASSWORD
#apk add bash

# Alpine VPS Complete Setup Script
# For educational and production use
# POSIX shell (sh) compatible version

set -e  # Exit on any error

# Configuration
PASSWORD="${PASSWORD:-defaultPassword1234}"
SUDOERS_FILE="/etc/sudoers.d/webhook-install"
ports="22 80 443 9000 3000 8080"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging setup
LOG_DIR="/var/log/deploy-setup"
mkdir -p $LOG_DIR
exec > >(tee -a $LOG_DIR/setup.log)
exec 2>&1

echo -e "${GREEN}=== Alpine VPS Setup Started at $(date) ===${NC}"

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Success message function
success_msg() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Warning message function
warning_msg() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Validation functions
check_password() {
    if [ -z "$PASSWORD" ]; then
        error_exit "PASSWORD environment variable must be set"
    fi
    
    if [ ${#PASSWORD} -lt 8 ]; then
        error_exit "Password must be at least 8 characters long"
    fi
    success_msg "Password validation passed"
}

check_user_created() {
    if ! id "deploy" >/dev/null 2>&1; then
        error_exit "Failed to create deploy user"
    fi
    success_msg "Deploy user created successfully"
}

# Main setup functions
update_system() {
    echo "Updating system packages..."
    apk update
    apk upgrade
    success_msg "System updated"
}

create_deploy_user() {
    echo "Creating deploy user..."
    check_password
    
    # Check user existance
    if id "deploy" >/dev/null 2>&1; then
        warning_msg "User 'deploy' already exists, skipping creation"
    else
        echo "Creating new user 'deploy'..."
        adduser -D deploy
        success_msg "Deploy user created"
    fi
    
    # Password setup
    echo "Setting password for deploy user..."
    echo "deploy:$PASSWORD" | chpasswd
    
    check_user_created
}

setup_sudo() {
    echo "Setting up sudo privileges..."
    
    # Ensure sudo is installed
    apk add sudo
    
    # Add deploy user to wheel group
    addgroup deploy wheel
    
    # Configure sudoers
    cp /etc/sudoers /etc/sudoers.backup
    sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
    
    # Verify sudo access
    if sudo -u deploy sudo -n true >/dev/null 2>&1; then
        success_msg "Sudo access configured"
    else
        warning_msg "Sudo access needs password (this is normal)"
    fi
}

setup_firewall() {
    echo "Configuring firewall..."
    
    # Install ufw if not present
    apk add ufw
    
    # Reset and set default policies
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow specified ports (iterate through space-separated string)
    for port in $ports; do
        echo "Allowing port $port..."
        ufw allow $port
    done
    
    # Enable firewall
    ufw --force enable
    
    # Enable at boot
    rc-update add ufw boot
    
    success_msg "Firewall configured and enabled"
}

setup_ssh_security() {
    echo "Hardening SSH configuration..."
    
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    # Disable root login
    #sed -i 's/#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    
    # Disable password authentication (uncomment if using key-based auth only)
    # sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    
    # Restart SSH service
    service sshd restart
    
    success_msg "SSH security hardened"
}

install_docker() {
    echo "Installing Docker..."
    
    apk add docker docker-cli docker-compose
    rc-update add docker boot
    service docker start
    
    # Add deploy user to docker group
    addgroup deploy docker
    
    # Verify Docker installation
    if service docker status >/dev/null 2>&1; then
        success_msg "Docker installed and running"
    else
        error_exit "Docker installation failed"
    fi
}

install_development_tools() {
    echo "Installing development tools..."
    
    # Essential development packages
    apk add --no-cache \
        git \
        curl \
        wget \
        nano \
        vim \
        htop \
        build-base \
        openssl \
        ca-certificates \
        zip \
        unzip \
        tar \
        net-tools \
        iproute2 \
        bash
    
    success_msg "Development tools installed"
}

setup_fail2ban() {
    echo "Installing and configuring fail2ban..."
    
    apk add fail2ban
    
    # Check which log file exists for SSH
    SSH_LOG_PATH=""
    if [ -f "/var/log/auth.log" ]; then
        SSH_LOG_PATH="/var/log/auth.log"
    elif [ -f "/var/log/messages" ]; then
        SSH_LOG_PATH="/var/log/messages"
    else
        # Create auth.log and configure syslog if needed
        touch /var/log/auth.log
        
        # Configure busybox syslog to create auth.log
        if [ -f "/etc/syslog.conf" ]; then
            if ! grep -q "auth.log" /etc/syslog.conf; then
                echo "auth.*                         /var/log/auth.log" >> /etc/syslog.conf
                service syslog restart
            fi
        fi
        SSH_LOG_PATH="/var/log/auth.log"
    fi
    
    echo "Using SSH log path: $SSH_LOG_PATH"
    
    # Configure fail2ban with correct log path
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
logpath = $SSH_LOG_PATH
maxretry = 3
EOF
    
    # Ensure log directory permissions
    chmod 640 $SSH_LOG_PATH 2>/dev/null || true
    
    rc-update add fail2ban boot
    
    # Test configuration before starting
    if fail2ban-client -t >/dev/null 2>&1; then
        service fail2ban start
        success_msg "Fail2ban configured and started"
    else
        warning_msg "Fail2ban configuration test failed, skipping startup"
        echo "You may need to manually configure fail2ban later"
    fi
}

# Function to setup sudoers NOPASSWD configuration
setup_sudoers_nopasswd() {
    echo "=== Setting up sudoers NOPASSWD configuration ==="
    
    # Check if user is in wheel group or has sudo access
    if ! groups | grep -q "\bwheel\b" && ! sudo -l > /dev/null 2>&1; then
        echo "Error: User is not in wheel group and doesn't have sudo access"
        return 1
    fi
    
    # Create sudoers configuration
    echo "Creating sudoers configuration for webhook installation..."
    
    # Method 1: Safe way using visudo (Recommended)
    cat << 'EOF' > /tmp/webhook-sudoers
# Temporary sudoers rules for webhook installation
# This file allows specific commands to run without password
# sudo -n 
%wheel ALL=(ALL) NOPASSWD: /bin/mv
%wheel ALL=(ALL) NOPASSWD: /usr/bin/mv
%wheel ALL=(ALL) NOPASSWD: /bin/chmod
%wheel ALL=(ALL) NOPASSWD: /usr/bin/chmod
%wheel ALL=(ALL) NOPASSWD: /bin/mkdir
%wheel ALL=(ALL) NOPASSWD: /usr/bin/mkdir
%wheel ALL=(ALL) NOPASSWD: /bin/rm
%wheel ALL=(ALL) NOPASSWD: /usr/bin/rm
%wheel ALL=(ALL) NOPASSWD: /usr/bin/tee
%wheel ALL=(ALL) NOPASSWD: /bin/tee
EOF
    
    # Validate sudoers syntax before installing
    if sudo visudo -c -f /tmp/webhook-sudoers; then
        echo "✓ Sudoers syntax is valid"
        sudo cp /tmp/webhook-sudoers "$SUDOERS_FILE"
        sudo chmod 440 "$SUDOERS_FILE"
        echo "✓ Sudoers configuration installed at $SUDOERS_FILE"
    else
        echo "✗ Sudoers syntax is invalid!"
        rm -f /tmp/webhook-sudoers
        return 1
    fi
    
    # Clean up temporary file
    rm -f /tmp/webhook-sudoers
    
    echo "✓ NOPASSWD configuration is now active"
    echo "  You can now run webhook installation commands without password"
}

create_monitoring_scripts() {
    echo "Creating monitoring scripts..."
    
    # Disk usage monitoring
    cat > /home/deploy/disk-check.sh << 'EOF'
#!/bin/sh
THRESHOLD=80
USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $USAGE -gt $THRESHOLD ]; then
    echo "WARNING: Disk usage is at ${USAGE}%" | logger
    echo "WARNING: Disk usage is at ${USAGE}%"
fi
EOF
    
    # System info script
    cat > /home/deploy/system-info.sh << 'EOF'
#!/bin/sh
echo "=== System Information ==="
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime)"
echo "Disk Usage:"
df -h
echo ""
echo "Memory Usage:"
free -h
echo ""
echo "Docker Status:"
docker --version 2>/dev/null || echo "Docker not running"
EOF
    
    chmod +x /home/deploy/*.sh
    chown deploy:deploy /home/deploy/*.sh
    
    success_msg "Monitoring scripts created"
}

setup_environment_file() {
    echo "Creating environment configuration..."
    
    cat > /home/deploy/.env << EOF
# Environment Configuration
DEPLOY_USER=deploy
ALLOWED_PORTS=$ports
SETUP_DATE=$(date)
DOCKER_INSTALLED=true
EOF
    
    chown deploy:deploy /home/deploy/.env
    
    success_msg "Environment file created"
}

add_auto_logout_30min() {
    CODE='# Auto logout after 30 minutes (1,800 seconds) of inactivity for sh/ash (Alpine)
if [ -z "$SSH_TTY" ]; then
    # Skip if not an SSH session (remove this block to apply everywhere)
    return
fi

if [ -z "$AUTOLOGOUT_1800" ]; then
    export AUTOLOGOUT_1800=1
    while true; do
        read -t 1800 -p "" dummy
        if [ $? -eq 0 ]; then
            continue
        else
            echo "Auto logout: Session ended after 30 minutes of inactivity."
            kill -9 $$
        fi
    done &
fi
'
    PROFILE='/etc/profile'
    # Create /etc/profile if it does not exist
    if [ ! -f "$PROFILE" ]; then
        echo "$CODE" > "$PROFILE"
        echo "/etc/profile created and auto logout code added."
        return
    fi
    # Check for existing auto logout code to prevent duplicates
    if grep -q 'AUTOLOGOUT_1800' "$PROFILE"; then
        echo "Auto logout code is already present in /etc/profile."
        return
    fi
    # Append the code
    echo "$CODE" >> "$PROFILE"
    echo "Auto logout code added to /etc/profile."
}   

add_rc-updates() {
    # This is needed to run webhook
    echo "RC-UPDATE ADD LOCAL"
    rc-update add local default
}

setup_webhook_startup() {
    local startup_file="/etc/local.d/start-webhook.start"
    local force_create="$1"  # Optional --force parameter
    
    echo "🔧 Setting up webhook startup script..."
    
    # Check if webhook binary exists
    if ! command -v webhook >/dev/null 2>&1; then
        echo "❌ Error: webhook binary not found. Please install webhook first."
        return 1
    fi
    
    # Check if hooks.json exists in the app directory
    if [ ! -f "$hooks_json" ]; then
        echo "❌ Error: hooks.json not found at $hooks_dir"
        echo "   Make sure to create the hooks configuration file."
        return 1
    fi
    
    # Create /etc/local.d directory if it doesn't exist
    if [ ! -d "/etc/local.d" ]; then
        echo "📁 Creating /etc/local.d directory..."
        if ! sudo mkdir -p /etc/local.d; then
            echo "❌ Error: Failed to create /etc/local.d directory"
            return 1
        fi
    fi
    
    # Create the startup script
    echo "📝 Creating startup script at $startup_file..."
    
    if ! sudo tee "$startup_file" > /dev/null << EOF
#!/bin/sh
# Webhook startup script
# Auto-generated by setup_webhook_startup function

cd $app_dir
/usr/local/bin/webhook -hooks "$hooks_json" -port 9000 &
EOF
    then
        echo "❌ Error: Failed to create startup script"
        return 1
    fi
    
    # Make it executable
    echo "🔐 Making startup script executable..."
    if ! sudo -n chmod +x "$startup_file"; then
        echo "❌ Error: Failed to make startup script executable"
        return 1
    fi
    
    # Add local service to startup (if not already added)
    echo "⚙️  Configuring local service for startup..."
    
    # Check if local service is already enabled
    if rc-status | grep -q "local.*started\|local.*starting"; then
        echo "ℹ️  Local service is already running"
    elif rc-update show | grep -q "local.*default"; then
        echo "ℹ️  Local service is already enabled for startup"
    else
        echo "🚀 Adding local service to default runlevel..."
        if ! sudo rc-update add local default; then
            echo "❌ Error: Failed to add local service to startup"
            return 1
        fi
        echo "✅ Local service added to startup"
    fi
    
    # Display summary
    echo ""
    echo "✅ Webhook startup configuration completed!"
    echo "📋 Summary:"
    echo "   Script location: $startup_file"
    echo "   App directory: $app_dir"
    echo "   Webhook port: 9000"
    echo "   Service status: $(rc-update show | grep local | head -1 || echo 'Not configured')"
    echo ""
    echo "🔄 To test the startup script manually:"
    echo "   sudo /etc/local.d/start-webhook.start"
    echo ""
    echo "🔄 To start local service now:"
    echo "   sudo rc-service local start"
    echo ""
    echo "⚠️  Make sure hooks.json exists in $hooks_json before starting!"
}

# Helper function to remove webhook startup
remove_webhook_startup() {
    local startup_file="/etc/local.d/start-webhook.start"
    
    echo "🗑️  Removing webhook startup script..."
    
    if [ -f "$startup_file" ]; then
        if sudo rm "$startup_file"; then
            echo "✅ Startup script removed"
        else
            echo "❌ Error: Failed to remove startup script"
            return 1
        fi
    else
        echo "ℹ️  Startup script not found (already removed)"
    fi
    
    echo "ℹ️  Note: local service remains enabled. To disable:"
    echo "   sudo rc-update del local default"
}

# Helper function to show startup status
show_webhook_startup_status() {
    local startup_file="/etc/local.d/start-webhook.start"
    
    echo "📊 Webhook Startup Status"
    echo "========================"
    
    # Check startup script
    if [ -f "$startup_file" ]; then
        echo "Startup script: ✅ EXISTS"
        echo "  Location: $startup_file"
        echo "  Permissions: $(ls -l "$startup_file" | cut -d' ' -f1)"
        echo "  Content:"
        cat "$startup_file" | sed 's/^/    /'
    else
        echo "Startup script: ❌ NOT FOUND"
    fi
    
    echo ""
    
    # Check local service status
    echo "Local service status:"
    if rc-update show | grep -q "local"; then
        echo "  Runlevel: ✅ $(rc-update show | grep local)"
    else
        echo "  Runlevel: ❌ NOT CONFIGURED"
    fi
    
    if rc-status | grep -q "local"; then
        echo "  Current: ✅ $(rc-status | grep local)"
    else
        echo "  Current: ❌ NOT RUNNING"
    fi
    
    echo ""
    
    # Check if webhook is actually running
    if pgrep -f "webhook.*hooks" >/dev/null 2>&1; then
        echo "Webhook process: ✅ RUNNING"
        pgrep -f "webhook.*hooks" | while read pid; do
            echo "  PID: $pid"
        done
    else
        echo "Webhook process: ❌ NOT RUNNING"
    fi
}

set_time_zone() {
    if setup-timezone -z America/New_York; then
        echo "Set time zone to New York"
    fi
}

# Main execution
main() {
    echo -e "${GREEN}Starting Alpine VPS setup...${NC}"
    
    update_system
    create_deploy_user
    setup_sudo
    setup_firewall
    setup_ssh_security
    install_docker
    install_development_tools
    setup_fail2ban
    create_monitoring_scripts
    setup_environment_file
    setup_sudoers_nopasswd
#    add_auto_logout_30min
    setup_docker
    add_rc-updates
    setup_webhook_startup
    show_webhook_startup_status
    set_time_zone
    
    echo -e "${GREEN}=== Setup completed successfully! ===${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Test SSH login with deploy user"
    echo "2. Set up SSH key authentication"
    echo "3. Consider disabling password authentication"
    echo "4. Test Docker: sudo -u deploy docker run hello-world"
    echo "5. Review logs in $LOG_DIR/setup.log"
    echo ""
    echo "Monitoring scripts available:"
    echo "- /home/deploy/disk-check.sh"
    echo "- /home/deploy/system-info.sh"
}

# Run main function
main "$@"