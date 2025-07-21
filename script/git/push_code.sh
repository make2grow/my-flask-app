#!/bin/bash

if [ -z "$1" ]; then
    # 2025-07-21 19:56:00 format
    MESSAGE="Auto commit: $(date '+%Y-%m-%d %H:%M:%S')"
else
    MESSAGE="$1"
fi

git add .
git commit -m "$MESSAGE"
git push -u origin main