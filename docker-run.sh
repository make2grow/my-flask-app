#!/bin/sh

cd /home/deploy/my-flask-app

#docker stop $(docker ps -q) 2>/dev/null
#docker rm $(docker ps -a -q) 2>/dev/null
rc-service docker restart

docker build -t flask-app .
docker run -d --name flask-app --restart=always -p 80:5000 flask-app