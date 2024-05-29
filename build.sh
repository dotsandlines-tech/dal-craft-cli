#!/bin/sh

IMAGE_NAME_BASE=dotsandlines/dal-craft-cli:v1.2.0-php8.1.28

IMAGE_NAME_A3CLOUD=${IMAGE_NAME_BASE}-a3cloud
docker buildx build --platform linux/amd64 -t ${IMAGE_NAME_A3CLOUD} --target cli-a3cloud .

IMAGE_NAME_BORGMATIC=${IMAGE_NAME_BASE}-borgmatic
docker buildx build --platform linux/amd64 -t ${IMAGE_NAME_BORGMATIC} --target cli-borgmatic .