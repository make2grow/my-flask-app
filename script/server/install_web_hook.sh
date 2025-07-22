#!/bin/sh
# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

app_dir="/home/deploy/my-flask-app"  # Using actual deploy user
hooks_dir="$app_dir/script/serve"
hooks_json="$hooks_dir/hooks.json"

install_webhook() {
    # Check if webhook is already installed
    if command -v webhook >/dev/null 2>&1; then
        echo "✅ Webhook is already installed!"
        echo "Current version: $(webhook -version 2>/dev/null || echo 'Version check failed')"
        return 0
    fi
    
    local arch=$(uname -m)
    local webhook_arch=""
    local download_url=""
    local temp_dir="/tmp"
    local install_dir="/usr/local/bin"
    
    echo "Detected architecture: $arch"
    
    # Map system architecture to webhook architecture naming
    case "$arch" in
        x86_64)
            webhook_arch="amd64"
            ;;
        aarch64|arm64)
            webhook_arch="arm64"
            ;;
        armv7l|armv6l)
            webhook_arch="armv6"
            ;;
        *)
            echo "Error: Unsupported architecture '$arch'"
            echo "Supported architectures: x86_64, aarch64, arm64, armv7l, armv6l"
            return 1
            ;;
    esac
    
    # Construct download URL and filename
    download_url="https://github.com/adnanh/webhook/releases/latest/download/webhook-linux-${webhook_arch}.tar.gz"
    local tar_file="webhook-linux-${webhook_arch}.tar.gz"
    
    echo "Installing webhook for $webhook_arch architecture..."
    
    # Change to temporary directory
    cd "$temp_dir" || {
        echo "Error: Cannot access temporary directory $temp_dir"
        return 1
    }
    
    # Download only if file doesn't exist
    if [ ! -f "$tar_file" ]; then
        echo "Downloading from: $download_url"
        if ! wget "$download_url"; then
            echo "Error: Failed to download webhook"
            return 1
        fi
    else
        echo "File $tar_file already exists, skipping download"
    fi
    
    # Debug: Check what's in the tar file
    echo "Contents of $tar_file:"
    tar -tzf "$tar_file"
    
    # Extract the tar.gz file
    if ! tar -xzf "$tar_file"; then
        echo "Error: Failed to extract $tar_file"
        return 1
    fi
    
    # Debug: Check what files were extracted
    echo "Files after extraction:"
    ls -la webhook*
    
    # Find the webhook binary (might be in subdirectory)
    local webhook_binary=""
    if [ -f "webhook" ]; then
        webhook_binary="webhook"
    elif [ -f "webhook-linux-${webhook_arch}/webhook" ]; then
        webhook_binary="webhook-linux-${webhook_arch}/webhook"
    else
        echo "Error: Cannot find webhook binary after extraction"
        echo "Available files:"
        find . -name "*webhook*" -type f
        return 1
    fi
    
    echo "Found webhook binary at: $webhook_binary"
    
    # Install the binary
    if ! sudo -n mv "$webhook_binary" "$install_dir/webhook"; then
        echo "Error: Failed to move webhook to $install_dir"
        return 1
    fi
    
    # Make it executable
    if ! sudo -n chmod +x "$install_dir/webhook"; then
        echo "Error: Failed to make webhook executable"
        return 1
    fi
    
    # Verify installation
    if command -v webhook >/dev/null 2>&1; then
        echo "✅ Webhook installed successfully!"
        echo "Version: $(webhook -version 2>/dev/null || echo 'Version check failed')"
    else
        echo "❌ Installation verification failed"
        return 1
    fi
}

start_webhook() {
    local port="9000"
    
    # Check if webhook binary exists
    if ! command -v webhook >/dev/null 2>&1; then
        echo "❌ Error: webhook binary not found. Please install webhook first."
        return 1
    fi
    
    # Check if hooks configuration file exists
    if [ ! -f "$hooks_json" ]; then
        echo "❌ Error: hooks configuration file not found at $hooks_file"
        return 1
    fi
    
    # Check if webhook is already running
    if pgrep -f "webhook.*hooks.*$hooks_json" >/dev/null 2>&1; then
        echo "✅ Webhook is already running"
        echo "Process info:"
        pgrep -f "webhook.*hooks.*$hooks_json" | while read pid; do
            echo "  PID: $pid"
            ps -p "$pid" -o pid,ppid,cmd --no-headers 2>/dev/null || echo "  Process details unavailable"
        done
        return 0
    fi
    
    # Check if port is already in use
    if command -v netstat >/dev/null 2>&1; then
        if netstat -ln 2>/dev/null | grep ":$port " >/dev/null; then
            echo "❌ Error: Port $port is already in use"
            echo "Processes using port $port:"
            netstat -lnp 2>/dev/null | grep ":$port " || echo "  Unable to determine process"
            return 1
        fi
    fi
    
    # Start webhook in background
    echo "🚀 Starting webhook..."
    echo "Command: webhook -hooks $hooks_json -port $port"
    
    # Start webhook in background and capture PID
    webhook -hooks "$hooks_json" -port "$port" >/dev/null 2>&1 &
    local webhook_pid=$!
    
    sleep 1  # Give it a moment to start
    
    # Verify it started successfully
    if kill -0 "$webhook_pid" 2>/dev/null; then
        echo "✅ Webhook started successfully!"
        echo "  PID: $webhook_pid"
        echo "  Port: $port"
        echo "  Hooks file: $hooks_json"
        echo "  Status: Running"
        
        # Save PID for later management (optional)
        echo "$webhook_pid" > /tmp/webhook.pid
    else
        echo "❌ Webhook failed to start"
        return 1
    fi
}

# Additional helper functions for webhook management
stop_webhook() {
    echo "🛑 Stopping webhook..."
    
    if pgrep -f "webhook.*hooks" >/dev/null 2>&1; then
        # Kill all webhook processes
        pgrep -f "webhook.*hooks" | while read pid; do
            echo "  Stopping PID: $pid"
            kill "$pid" 2>/dev/null
        done
        
        # Wait a moment and check if they're gone
        sleep 1
        if pgrep -f "webhook.*hooks" >/dev/null 2>&1; then
            echo "  Force killing remaining processes..."
            pkill -f "webhook.*hooks" 2>/dev/null
        fi
        
        echo "✅ Webhook stopped"
        rm -f /tmp/webhook.pid
    else
        echo "ℹ️  Webhook is not running"
    fi
}

status_webhook() {
    echo "📊 Webhook Status Check"
    echo "===================="
    
    if pgrep -f "webhook.*hooks" >/dev/null 2>&1; then
        echo "Status: ✅ RUNNING"
        echo ""
        echo "Process details:"
        pgrep -f "webhook.*hooks" | while read pid; do
            echo "  PID: $pid"
            if command -v ps >/dev/null 2>&1; then
                ps -p "$pid" -o pid,ppid,etime,cmd --no-headers 2>/dev/null | sed 's/^/    /'
            fi
        done
        
        # Check port if netstat is available
        if command -v netstat >/dev/null 2>&1; then
            echo ""
            echo "Port usage:"
            netstat -ln 2>/dev/null | grep ":9000 " | sed 's/^/  /' || echo "  Port info unavailable"
        fi
    else
        echo "Status: ❌ NOT RUNNING"
    fi
    
    echo ""
    echo "Hooks file: /home/deploy/hooks.json"
    if [ -f "/home/deploy/hooks.json" ]; then
        echo "  Status: ✅ EXISTS"
    else
        echo "  Status: ❌ NOT FOUND"
    fi
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
    
    # Check if file already exists and force flag is not set
    if [ -f "$startup_file" ] && [ "$force_create" != "--force" ]; then
        echo "ℹ️  Startup script already exists at $startup_file"
        echo "   Use 'setup_webhook_startup --force' to overwrite."
        echo "   Current content:"
        cat "$startup_file" | sed 's/^/     /'
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
    if ! sudo chmod +x "$startup_file"; then
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
    echo "⚠️  Make sure hooks.json exists in $app_dir before starting!"
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

main() {
    echo -e "${GREEN}WebHook Setup${NC}"
    
    install_webhook
    
    start_webhook
    status_webhook
    
    setup_webhook_startup
    show_webhook_startup_status
    
    echo -e "${GREEN}=== Next Step: ===${NC}"
    echo " 1. Go to your GitHub repo → **Settings → Webhooks**"
    echo " 2. Add webhook:"
    echo "   - Payload URL: http://<your-ip>:9000/hooks/flask-hook"
    echo "   - Content Type: application/json"
    echo "   - Secret (optional, but recommended)"
}

# Run main function
main "$@"
