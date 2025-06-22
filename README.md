# Dev Container for COVESA libraries

## Build

Supports multiple basse distros:
```bash
# Build with Fedora 42 as base
podman build --build-arg BASE_STAGE=fedora-base --target fedora-final -t my-app:fedora .

# Build with Ubuntu 24 as base
podman build --build-arg BASE_STAGE=ubuntu-base --target ubuntu-final -t my-app:ubuntu .

# Build with Alpine latest as base
podman build --build-arg BASE_STAGE=alpine-base --target alpine-final -t my-app:alpine .
```