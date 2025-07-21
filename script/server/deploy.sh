cd /home/deploy/my-flask-app
git pull origin main
docker build -t flask-app .
docker stop flask-running
docker rm flask-running
docker run -d --name flask-running -p 80:5000 flask-app
