#!/bin/sh
# usage: next-version.sh <previous X.Y.Z> <commit subject>
# Conventional commits: "type!:" is a major bump, "feat" a minor one, anything else a patch.
prev=$1 subject=$2
IFS=. read -r major minor patch <<EOV
$prev
EOV
case $subject in
  [a-z]*'!:'* | [a-z]*')!:'*) major=$((major + 1)) minor=0 patch=0 ;;
  feat:* | 'feat('*) minor=$((minor + 1)) patch=0 ;;
  *) patch=$((patch + 1)) ;;
esac
echo "$major.$minor.$patch"
