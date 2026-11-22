#!/bin/bash

# Helper script to build the image with metadata

set -e

# ============================================================================
# DEFAULT VALUES - Edit these to change defaults
# ============================================================================
DEFAULT_VERSION="1.0.0"
DEFAULT_ALPINE_VERSION="3.24.4"                       # Alpine base image version
                                                      # Repository: https://hub.docker.com/_/alpine
                                                      # Latest release: 3.24.4 (as of 2026-11-22)
DEFAULT_BTOP_VERSION="1.4.8"                          # btop++ version (git tag without "v"), compiled from source
                                                      # Repository: https://github.com/aristocratos/btop
                                                      # Releases: https://github.com/aristocratos/btop/releases
# ttyd and tini are not pinned: the latest version in the Alpine branch is used.
# The ttyd version is resolved at build time (see resolve_alpine_package) and recorded in the image labels.
DEFAULT_PLATFORMS="linux/amd64,linux/arm64"
DEFAULT_BUILDER_NAME="btop-plus-plus-builder"
DEFAULT_REGISTRY=""  # Empty for local build, or set to "docker.io/username" for Docker Hub
DEFAULT_IMAGE_NAME="btop-plus-plus"
# ============================================================================

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Help function
show_help() {
    cat << EOF
btop-plus-plus - Build Script

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    --version VERSION       Image version (default: $DEFAULT_VERSION)
    --alpine-version VER    Alpine base image version (default: $DEFAULT_ALPINE_VERSION)
    --btop-version VER      btop++ version to compile, without "v" (default: $DEFAULT_BTOP_VERSION)
    --ttyd-version VER      Force a ttyd version from Alpine repo, e.g. "1.7.7-r0"
                            (default: latest in the Alpine branch, resolved at build time)
    --platform PLATFORM     Target platform(s) (default: $DEFAULT_PLATFORMS)
                            Use 'native' to build only for current platform
    --registry REGISTRY     Registry/repository (e.g., docker.io/username or ghcr.io/username)
                            If not specified, builds locally only
    --image-name NAME       Image name (default: $DEFAULT_IMAGE_NAME)
    --push                  Push image to registry after build (requires --registry and docker login)
    --local                 Build locally only, do not push (default behavior)
    --no-cache              Build without using cache

Environment Variables:
    VERSION                 Image version
    ALPINE_VERSION          Alpine base image version
    BTOP_VERSION            btop++ version
    TTYD_VERSION            Force a ttyd version (default: latest in the Alpine branch)
    BUILD_DATE              Build date (auto-generated if not set)
    REGISTRY                Registry/repository
    IMAGE_NAME              Image name

Note: Default values can be changed at the top of this script.

Build Modes:
    1. LOCAL BUILD (default):
       $0
       $0 --local
       Builds image locally, tags as btop-plus-plus:VERSION and btop-plus-plus:latest

    2. BUILD AND PUSH TO REGISTRY:
       $0 --registry docker.io/username --push
       $0 --registry ghcr.io/username --push
       Builds and pushes to remote registry

Examples:
    # Local build (default)
    $0
    $0 --platform native

    # Local build with a different btop++ version
    $0 --btop-version 1.4.7

    # Build and push to Docker Hub (amd64 + arm64)
    $0 --registry docker.io/username --push

EOF
}

# Parse arguments
PLATFORMS="$DEFAULT_PLATFORMS"
PUSH=false
LOCAL_BUILD=true
NO_CACHE=""
REGISTRY=""
IMAGE_NAME="$DEFAULT_IMAGE_NAME"
BUILD_DATE=${BUILD_DATE:-$(date -u +'%Y-%m-%dT%H:%M:%SZ')}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help|--h)
            show_help
            exit 0
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --alpine-version)
            ALPINE_VERSION="$2"
            shift 2
            ;;
        --btop-version)
            BTOP_VERSION="${2#v}"
            shift 2
            ;;
        --ttyd-version)
            TTYD_VERSION="$2"
            shift 2
            ;;
        --platform)
            PLATFORMS="$2"
            shift 2
            ;;
        --registry)
            REGISTRY="$2"
            LOCAL_BUILD=false
            shift 2
            ;;
        --image-name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --push)
            PUSH=true
            LOCAL_BUILD=false
            shift
            ;;
        --local)
            LOCAL_BUILD=true
            PUSH=false
            REGISTRY=""  # Clear registry when using --local
            shift
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set default values (can be overridden by environment variables or arguments)
VERSION=${VERSION:-$DEFAULT_VERSION}
ALPINE_VERSION=${ALPINE_VERSION:-$DEFAULT_ALPINE_VERSION}
BTOP_VERSION=${BTOP_VERSION:-$DEFAULT_BTOP_VERSION}
BUILDER_NAME="$DEFAULT_BUILDER_NAME"
REGISTRY=${REGISTRY:-$DEFAULT_REGISTRY}
IMAGE_NAME=${IMAGE_NAME:-$DEFAULT_IMAGE_NAME}

# Determine build mode (--local takes precedence)
if [ "$LOCAL_BUILD" = true ]; then
    REGISTRY=""  # Clear registry for local builds
fi

# Validate push/registry requirements (two modes only: local build | build+push)
if [ "$PUSH" = true ] && [ -z "$REGISTRY" ]; then
    echo -e "${YELLOW}ERROR: --push requires --registry to be specified${NC}"
    echo "Example: $0 --registry docker.io/username --push"
    exit 1
fi
if [ -n "$REGISTRY" ] && [ "$PUSH" = false ]; then
    echo -e "${YELLOW}ERROR: --registry must be used with --push${NC}"
    echo "Omit --registry for local build, or use: $0 --registry $REGISTRY --push"
    exit 1
fi

# For local builds, switch to native platform if multi-platform was specified
if [ "$LOCAL_BUILD" = true ] && echo "$PLATFORMS" | grep -q ","; then
    echo -e "${YELLOW}WARNING: Multi-platform builds cannot be loaded locally${NC}"
    echo -e "${YELLOW}Switching to native platform for local build${NC}"
    echo ""
    PLATFORMS="native"
fi

# buildx is only needed for non-native builds
if [ "$PLATFORMS" != "native" ]; then
    # Check if buildx is available
    if ! docker buildx version > /dev/null 2>&1; then
        echo -e "${YELLOW}ERROR: docker buildx not found (required for --platform / --push)${NC}"
        exit 1
    fi

    # Create buildx builder if it doesn't exist
    if ! docker buildx ls | grep -q "$BUILDER_NAME"; then
        echo -e "${BLUE}Creating buildx builder: $BUILDER_NAME${NC}"
        docker buildx create --name "$BUILDER_NAME" --use
    else
        echo -e "${BLUE}Using existing buildx builder: $BUILDER_NAME${NC}"
        docker buildx use "$BUILDER_NAME"
    fi

    # Bootstrap builder if needed
    docker buildx inspect --bootstrap > /dev/null 2>&1 || true
fi

# Resolve the latest version of an Alpine package in the base image branch (e.g. v3.24)
# Prints nothing if it cannot be resolved (the build then installs the latest without recording it)
resolve_alpine_package() {
    local pkg_name="$1"
    local branch
    branch=$(echo "$ALPINE_VERSION" | cut -d'.' -f1,2)
    curl -sf "https://dl-cdn.alpinelinux.org/alpine/v${branch}/community/x86_64/APKINDEX.tar.gz" 2>/dev/null | \
        tar -xzO APKINDEX 2>/dev/null | \
        awk -v p="$pkg_name" '/^P:/{n=substr($0,3)} /^V:/{if(n==p){print substr($0,3); exit}}' || true
}

if [ -z "$TTYD_VERSION" ]; then
    TTYD_VERSION=$(resolve_alpine_package "ttyd")
    if [ -z "$TTYD_VERSION" ]; then
        echo -e "${YELLOW}WARNING: Could not resolve the ttyd version; installing latest without recording it in labels${NC}"
    fi
fi

echo -e "${BLUE}=== Building btop-plus-plus Image ===${NC}"
echo "Version: $VERSION"
echo "Build Date: $BUILD_DATE"
echo "Base Image: alpine:${ALPINE_VERSION}"
echo "btop++: v${BTOP_VERSION} (compiled from source)"
echo "ttyd: ${TTYD_VERSION:-latest from Alpine repo}"
echo "tini: latest from Alpine repo"
echo "Platforms: $PLATFORMS"
if [ "$LOCAL_BUILD" = true ]; then
    echo -e "${GREEN}Build mode: LOCAL${NC}"
else
    echo -e "${YELLOW}Build mode: REGISTRY${NC}"
    echo "Registry: $REGISTRY"
    echo -e "${YELLOW}Push to registry: ENABLED${NC}"
fi
echo ""

# Build arguments
BUILD_ARGS=(
    --build-arg "BUILD_DATE=$BUILD_DATE"
    --build-arg "VERSION=$VERSION"
    --build-arg "ALPINE_VERSION=$ALPINE_VERSION"
    --build-arg "BTOP_VERSION=$BTOP_VERSION"
    --build-arg "TTYD_VERSION=$TTYD_VERSION"
)

# Build image tags
if [ "$LOCAL_BUILD" = true ]; then
    TAGS=(
        -t "${IMAGE_NAME}:${VERSION}"
        -t "${IMAGE_NAME}:latest"
    )
else
    # Registry tags only (do not add local tags when pushing — buildx would push them to docker.io and fail)
    REGISTRY="${REGISTRY%/}"
    TAGS=(
        -t "${REGISTRY}/${IMAGE_NAME}:${VERSION}"
        -t "${REGISTRY}/${IMAGE_NAME}:latest"
    )
fi

# Build command
if [ "$PLATFORMS" = "native" ]; then
    # Single platform build (faster, no buildx needed)
    echo -e "${BLUE}Building for native platform...${NC}"
    docker build \
        "${BUILD_ARGS[@]}" \
        "${TAGS[@]}" \
        $NO_CACHE \
        .
elif [ "$PUSH" = true ]; then
    echo -e "${BLUE}Building for platforms: $PLATFORMS${NC}"
    echo -e "${BLUE}Building and pushing to registry: $REGISTRY${NC}"
    docker buildx build \
        --platform "$PLATFORMS" \
        "${BUILD_ARGS[@]}" \
        "${TAGS[@]}" \
        $NO_CACHE \
        --push \
        .
else
    # Build locally (load to local Docker) - single platform only
    echo -e "${BLUE}Building for platform: $PLATFORMS${NC}"
    docker buildx build \
        --platform "$PLATFORMS" \
        "${BUILD_ARGS[@]}" \
        "${TAGS[@]}" \
        $NO_CACHE \
        --load \
        .
fi

echo ""
if [ "$PUSH" = true ]; then
    echo -e "${GREEN}=== Build and Push Complete ===${NC}"
    echo "Images pushed to registry:"
    echo "  - ${REGISTRY}/${IMAGE_NAME}:${VERSION}"
    echo "  - ${REGISTRY}/${IMAGE_NAME}:latest"
    echo ""
    echo "To view supported platforms:"
    echo "  docker buildx imagetools inspect ${REGISTRY}/${IMAGE_NAME}:${VERSION}"
else
    echo -e "${GREEN}=== Build Complete ===${NC}"
    echo "Images created locally:"
    echo "  - ${IMAGE_NAME}:${VERSION}"
    echo "  - ${IMAGE_NAME}:latest"
    echo ""
    echo "To view image labels:"
    echo "  docker inspect ${IMAGE_NAME}:${VERSION} --format '{{json .Config.Labels}}'"
fi
