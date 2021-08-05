#!/bin/sh

IMAGE_NAME=docker-craftcms-cli:php-8.0-borgmatic-1.5.13
docker build -t ${IMAGE_NAME} .

