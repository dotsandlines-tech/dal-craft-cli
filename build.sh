#!/bin/sh

IMAGE_NAME=dotsandlines/dal-craft-cli:v1.1.2-php8.0
docker build -t ${IMAGE_NAME} .

