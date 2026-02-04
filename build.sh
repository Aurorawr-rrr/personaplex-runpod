#!/bin/bash
# PersonaPlex RunPod Build Script

set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Check required variables
if [ -z "$DOCKER_USERNAME" ]; then
    echo "Error: DOCKER_USERNAME not set"
    echo "Either set it in .env or export DOCKER_USERNAME=yourusername"
    exit 1
fi

IMAGE_NAME="${DOCKER_USERNAME}/personaplex-runpod"
TAG="${1:-latest}"

echo "=========================================="
echo "PersonaPlex RunPod Build"
echo "=========================================="
echo "Image: ${IMAGE_NAME}:${TAG}"
echo ""

# Build options
BUILD_ARGS=""
if [ -n "$HF_TOKEN" ]; then
    echo "HF_TOKEN found - model will be pre-downloaded (larger image, faster cold start)"
    read -p "Pre-download model into image? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        BUILD_ARGS="--build-arg HF_TOKEN=${HF_TOKEN}"
    fi
fi

echo ""
echo "Building Docker image..."
docker build ${BUILD_ARGS} -t ${IMAGE_NAME}:${TAG} .

echo ""
echo "=========================================="
echo "Build complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Test locally (optional):"
echo "   docker run --gpus all -p 8998:8998 -e HF_TOKEN=\$HF_TOKEN ${IMAGE_NAME}:${TAG}"
echo ""
echo "2. Push to Docker Hub:"
echo "   docker login"
echo "   docker push ${IMAGE_NAME}:${TAG}"
echo ""
echo "3. Create RunPod Endpoint at:"
echo "   https://www.runpod.io/console/serverless"
echo "   Container Image: ${IMAGE_NAME}:${TAG}"
echo ""
