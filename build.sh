#!/bin/sh
set -e
IMAGE=$(cat IMAGENAME);
if test -z "$IMAGE"; then
	echo "Problem reading image name from file IMAGENAME";
	exit 1;
fi

if docker images | grep -q "$IMAGE"; then
	docker image rm "$IMAGE";
fi

docker build . -t "$IMAGE"
echo docker image push $IMAGE
