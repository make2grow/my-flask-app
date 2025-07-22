#!/bin/bash

LOG_FILE="/home/deploy/deploy.log"
DATE=$(date '+%Y-%m-%d:%H:%M:%S')

log() {
  echo "[$DATE] $1" | tee -a "$LOG_FILE"
}

run() {
  eval "$1" >>"$LOG_FILE" 2>&1
  if [ $? -eq 0 ]; then
    log "✓ $2 OK"
  else
    log "✗ $2 FAILED"
    exit 1
  fi
}

log "Deployment started"
cd /home/deploy/my-flask-app || { log "✗ Failed to change directory"; exit 1; }

run "git pull origin main" "Git pull"

run "docker build -t flask-app ." "Docker build"

run "docker stop flask-running || true" "Stop existing container"
run "docker rm flask-running || true" "Remove existing container"

run "docker run -d --name flask-running --restart always -p 80:5000 flask-app" "Run container"

log "Deployment completed"