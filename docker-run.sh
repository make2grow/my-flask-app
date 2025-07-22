#!/bin/sh

cd /home/deploy/my-flask-app

docker stop flask-running
docker rm flask-running

docker build -t flask-app .
docker run -d --name flask-running --restart=always -p 80:5000 flask-app