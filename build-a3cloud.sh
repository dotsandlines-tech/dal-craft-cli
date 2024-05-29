#!/bin/sh

IMAGE_NAME=dotsandlines/dal-craft-cli:v1.1.2-php8.0-a3cloud-v0.0.1
docker buildx build --platform linux/amd64 -t ${IMAGE_NAME} . -f Dockerfile-a3cloud

docker tag ${IMAGE_NAME} eu.gcr.io/a3cloud-192413/${IMAGE_NAME}
docker push eu.gcr.io/a3cloud-192413/${IMAGE_NAME}

