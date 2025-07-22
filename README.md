# For Local

```bash
cd YOUR_LOCAL_REPOSITORY
mkdir my-flask-app
cd my-flask-app

git init
git remote add origin https://github.com/make2grow/my-flask-app
git pull origin main
git branch --set-upstream-to=origin/main
```

# For Server

```bash
cd $HOME
mkdir my-flask-app
cd my-flask-app

git init
git remote add origin https://github.com/make2grow/my-flask-app
git pull origin main
git branch --set-upstream-to=origin/main
```

# SYNC Local & Server
From local

```bash
sh script/git/push_code.sh  

or

sh script/git/push_code.sh  "YOUR COMMIT COMMENT"
```

From server

```bash
git pull
```

Then rebuild the docker: use docker-run.sh

```bash
docker build -t flask-app .
docker run -d -p 80:5000 flask-app
```

Check docker is running OK
```bash
> docker ps
CONTAINER ID   IMAGE       COMMAND                  CREATED          STATUS          PORTS                                     NAMES
800891227c0d   flask-app   "flask run --host=0.…"   50 seconds ago   Up 49 seconds   
```

Check if you can access the web server.

```bash
curl -v http://localhost:80
```

# Automation using WebHook

From server
