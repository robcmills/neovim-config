#!/bin/bash

PATTERN="onDragOver"
REPO_DIR="/Users/robcmills/src/openspace"
SEARCH_DIR="web/icedemon/src/js"
# 46s
# 8s

start=$(date +%s)

cd "$REPO_DIR"

rg --vimgrep "$PATTERN" \
  --color=never \
  --no-heading \
  --with-filename \
  --line-number \
  --column \
  --ignore-case \
  "$SEARCH_DIR" \
| awk -F ':' '{print $1" "$2}' \
| xargs -I {} -P 8 bash -c '
  read file line <<< "$1"
  commit_hash=$(git blame -L ${line},${line} -- "$file" | awk "{print \$1}")
  commit_date=$(git show -s --format=%ci "$commit_hash")
  echo "$commit_date $file:$line"
' _ {} \
| sort

# benchmark
end=$(date +%s)
duration=$((end - start))
echo "Script took $duration seconds to run."
