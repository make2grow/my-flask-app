docker build -t flask-app .
docker run -d -p 80:5000 flask-app