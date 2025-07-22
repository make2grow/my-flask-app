#!/bin/sh

cd /home/deploy/my-flask-app

#docker stop flask-running
#docker rm flask-running

#docker build -t flask-app .
#docker run -d --name flask-running --restart=always -p 80:5000 flask-app

# Only build if image doesn't exist
if ! docker image inspect flask-app >/dev/null 2>&1; then
    docker build -t flask-app .
fi

# Only run if container doesn't already exist
if ! docker ps -a --format '{{.Names}}' | grep -q '^flask-running$'; then
    docker run -d --name flask-running --restart=always -p 80:5000 flask-app
fi