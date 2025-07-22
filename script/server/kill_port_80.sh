#!/bin/bash

kill_port_80() {
    local force="$1"  # --force option enables forced mode
    
    echo "🔍 Checking port 80 usage..."
    
    # Check for processes using port 80
    local pids=$(sudo lsof -t -i:80 2>/dev/null)
    
    if [ -z "$pids" ]; then
        echo "✅ Port 80 is already free!"
        return 0
    fi
    
    echo "📋 Processes using port 80:"
    for pid in $pids; do
        echo "  PID: $pid"
        if ps -p "$pid" -o pid,user,comm,cmd --no-headers 2>/dev/null; then
            ps -p "$pid" -o pid,user,comm,cmd --no-headers | sed 's/^/    /'
        fi
    done
    echo ""
    
    # If not in forced mode, ask for confirmation
    if [ "$force" != "--force" ]; then
        echo "⚠️  This will terminate the above processes!"
        echo "🤔 Are you sure? (y/N)"
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                echo "👍 Proceeding with termination..."
                ;;
            *)
                echo "❌ Aborted by user"
                return 1
                ;;
        esac
    fi
    
    # Step-by-step termination
    echo "🛑 Step 1: Graceful termination (SIGTERM)..."
    for pid in $pids; do
        echo "  Sending SIGTERM to PID: $pid"
        sudo kill "$pid" 2>/dev/null
    done
    
    # Wait for 3 seconds
    echo "⏳ Waiting 3 seconds..."
    sleep 3
    
    # Check for any remaining processes
    local remaining_pids=$(sudo lsof -t -i:80 2>/dev/null)
    
    if [ -n "$remaining_pids" ]; then
        echo "⚡ Step 2: Force termination (SIGKILL)..."
        for pid in $remaining_pids; do
            echo "  Force killing PID: $pid"
            sudo kill -9 "$pid" 2>/dev/null
        done
        
        sleep 1
    fi
    
    # Final check
    local final_check=$(sudo lsof -t -i:80 2>/dev/null)
    
    if [ -z "$final_check" ]; then
        echo "✅ Port 80 is now free!"
        return 0
    else
        echo "❌ Some processes are still running on port 80:"
        sudo lsof -i:80
        return 1
    fi
}

# Usage help
show_usage() {
    echo "Usage: $0 [--force]"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompt"
    echo ""
    echo "Examples:"
    echo "  $0          # Interactive mode with confirmation"
    echo "  $0 --force  # Force mode without confirmation"
}

# Main execution
case "$1" in
    --help|-h)
        show_usage
        ;;
    --force)
        kill_port_80 --force
        ;;
    "")
        kill_port_80
        ;;
    *)
        echo "❌ Unknown option: $1"
        show_usage
        exit 1
        ;;
esac
