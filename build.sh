#!/bin/sh

IMAGE_NAME=docker-craftcms-cli:php-7.4-borgmatic-1.5.13
docker build -t ${IMAGE_NAME} .

