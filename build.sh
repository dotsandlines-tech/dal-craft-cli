#!/bin/sh

IMAGE_NAME_BASE=dotsandlines/dal-craft-cli:v1.2.3-php7.4.33

IMAGE_NAME_A3CLOUD=${IMAGE_NAME_BASE}-a3cloud
docker buildx build --platform linux/amd64 -t ${IMAGE_NAME_A3CLOUD} --target cli-a3cloud .

IMAGE_NAME_BORGMATIC=${IMAGE_NAME_BASE}-borgmatic
docker buildx build --platform linux/amd64 -t ${IMAGE_NAME_BORGMATIC} --target cli-borgmatic .

docker tag ${IMAGE_NAME_A3CLOUD} eu.gcr.io/a3cloud-192413/${IMAGE_NAME_A3CLOUD}
docker tag ${IMAGE_NAME_BORGMATIC} eu.gcr.io/a3cloud-192413/${IMAGE_NAME_BORGMATIC}

docker push eu.gcr.io/a3cloud-192413/${IMAGE_NAME_A3CLOUD}
docker push eu.gcr.io/a3cloud-192413/${IMAGE_NAME_BORGMATIC}
