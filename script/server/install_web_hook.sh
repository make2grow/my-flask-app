#!/bin/sh
# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

app_dir="/home/deploy/my-flask-app"  # Using actual deploy user
hooks_dir="$app_dir/script/server"
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
        echo "❌ Error: hooks configuration file not found at $hooks_json"
        return 1
    fi
    
    echo "🔍 Checking current webhook status..."
    
    # status_webhook 
    if pgrep -f "webhook.*hooks" >/dev/null 2>&1; then
        echo "📊 Current webhook status:"
        echo "  Status: 🟡 RUNNING (will be restarted)"
        
        pgrep -f "webhook.*hooks" | while read pid; do
            echo "  Current PID: $pid"
        done
        
        echo ""
        echo "🔄 Stopping webhook service before starting ..."
        stop_webhook  
        echo ""
    else
        echo "📊 Current status: ⚫ NOT RUNNING"
        echo "🚀 Starting fresh webhook instance..."
    fi
    
    # Double-check port availability
    if command -v netstat >/dev/null 2>&1; then
        if netstat -ln 2>/dev/null | grep ":$port " >/dev/null; then
            echo "❌ Error: Port $port is still in use"
            return 1
        fi
    fi
    
    # Start webhook
    echo "▶️  Launching webhook..."
    webhook -hooks "$hooks_json" -port "$port" -verbose -hotreload > /home/deploy/webhook.log 2>&1 &
    local webhook_pid=$!
    
    sleep 1
    
    # Verify startup
    if kill -0 "$webhook_pid" 2>/dev/null; then
        echo "✅ Webhook started successfully!"
        echo "  🆔 PID: $webhook_pid"
        echo "  🔌 Port: $port"
        echo "  📁 Config: $hooks_json"
        
        # Save PID and show final status
        echo "$webhook_pid" > /tmp/webhook.pid
        
        echo ""
        echo "📊 Final status verification:"
        # status_webhook check again
        if pgrep -f "webhook.*hooks" >/dev/null 2>&1; then
            echo "  Status: ✅ CONFIRMED RUNNING"
        else
            echo "  Status: ❌ STATUS CHECK FAILED"
        fi
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

main() {
    echo -e "${GREEN}WebHook Setup${NC}"
    
    install_webhook
    start_webhook
    
    # Check server-first-setup.sh for setup_webhook_startup function
    #setup_webhook_startup
    #show_webhook_startup_status
    
    echo -e "${GREEN}=== Next Step: ===${NC}"
    echo " 1. Go to your GitHub repo → **Settings → Webhooks**"
    echo " 2. Add webhook:"
    echo "   - Payload URL: http://<your-ip>:9000/hooks/flask-hook"
    echo "   - Content Type: application/json"
    echo "   - Secret (optional, but recommended)"
}

# Run main function
main "$@"
