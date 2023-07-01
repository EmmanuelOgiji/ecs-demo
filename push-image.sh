#!/usr/bin/env bash
set -x
echo "Pulling image from GHCR"
docker pull ghcr.io/emmanuelogiji/cloudboosta-flask-app:0.2.0
echo "Logging into ECR"
aws ecr get-login-password --region eu-west-2 | docker login --username AWS --password-stdin "$REGISTRY"
echo "Tag image for ECR"
docker tag ghcr.io/emmanuelogiji/cloudboosta-flask-app:0.2.0 "$REPO_URL":latest
echo "Pushing to ECR"
docker push "$REPO_URL":latest