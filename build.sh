#!/bin/sh

IMAGE_NAME=dotsandlines/dal-craft-cli:v1.2.0-php8.1
docker build -t ${IMAGE_NAME} .

