#!/bin/bash

# logfile
LOG_FILE="/home/deploy/deploy.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] Deployment started" >> $LOG_FILE

#  current directory
pwd >> $LOG_FILE

# git pull
git pull origin main >> $LOG_FILE 2>&1

echo "[$DATE] Deployment completed" >> $LOG_FILE

cd /home/deploy/my-flask-app
git pull origin main
docker build -t flask-app .
docker stop flask-running
docker rm flask-running
docker run -d --name flask-running -p 80:5000 flask-app
