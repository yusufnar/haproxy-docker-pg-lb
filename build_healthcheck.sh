#!/bin/bash
set -e

# Default registry if not provided
REGISTRY=${1:-"yusufnar"} # Defaults to 'yusufnar' if no argument is passed (assuming Docker Hub username)
IMAGE_NAME="haproxy-healthcheck"
TAG="latest"
FULL_IMAGE_NAME="$REGISTRY/$IMAGE_NAME:$TAG"

echo "Building image: $FULL_IMAGE_NAME"
docker build -t $FULL_IMAGE_NAME -f Dockerfile.healthcheck .

echo ""
echo "To push this image to your registry, run:"
echo "  docker push $FULL_IMAGE_NAME"
echo ""
echo "Don't forget to update k8s/healthcheck.yaml with: image: $FULL_IMAGE_NAME"
