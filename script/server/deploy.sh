#!/bin/bash
LOG_FILE="/home/deploy/deploy.log"
DATE=$(date '+%Y-%m-%d:%H:%M:%S')
export HOME="/root"  # or use /home/deploy
export USER="root"

log() {
  echo "[$DATE] $1" | tee -a "$LOG_FILE"
}

run() {
  echo "[$DATE] Executing: $1" | tee -a "$LOG_FILE"
  eval "$1" >>"$LOG_FILE" 2>&1
  local exit_code=$?
  if [ $exit_code -eq 0 ]; then
    log "✓ $2 OK"
  else
    log "✗ $2 FAILED (exit code: $exit_code)"
    # Log the last few lines for debugging
    echo "[$DATE] Last few lines of error:" | tee -a "$LOG_FILE"
    tail -5 "$LOG_FILE" | tee -a "$LOG_FILE"
    exit 1
  fi
}

log "==================== Deployment started ===================="
log "User: $(whoami)"
log "Working directory: $(pwd)"
log "PATH: $PATH"
log "HOME: $HOME"

cd /home/deploy/my-flask-app || { log "✗ Failed to change directory"; exit 1; }

# Add debugging for git
log "Git status check:"
git status >> "$LOG_FILE" 2>&1

log "Git remote check:"
git remote -v >> "$LOG_FILE" 2>&1
run "git config --global --add safe.directory /home/deploy/my-flask-app" "Git safe directory config"
run "git pull origin main" "Git pull"
# ... rest of your script

run "docker build -t flask-app ." "Docker build"

run "docker stop flask-running || true" "Stop existing container"
run "docker rm flask-running || true" "Remove existing container"

run "docker run -d --name flask-running --restart always -p 80:5000 flask-app" "Run container"

log "Deployment completed"