#!/bin/sh
set -e
docker build . -t jdimpson/podcatcher
echo docker image push jdimpson/podcatcher
