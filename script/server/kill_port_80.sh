sudo lsof -i :80
sudo lsof -t -i:80 | xargs -r sudo kill
sudo lsof -i :80