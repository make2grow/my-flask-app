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
git pull origin main
```