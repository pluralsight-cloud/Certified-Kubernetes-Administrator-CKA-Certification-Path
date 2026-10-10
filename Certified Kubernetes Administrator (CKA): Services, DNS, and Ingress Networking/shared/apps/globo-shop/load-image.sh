#!/usr/bin/env bash
#================================================================
# Globomantics parts shop -- get the image onto your lab nodes.
#
# Run this from your HOST (the machine with Docker), not from a node.
#
# WHY this exists: the manifests set `imagePullPolicy: IfNotPresent`, which means
# a node that already has the image never contacts a registry at all. So there are
# two ways to get it there, and this script does whichever one works for you:
#
#   1. PULL  -- the node pulls from ghcr.io. Needs internet on the nodes AND a
#               published manifest for the node's CPU architecture.
#   2. BUILD -- you build locally and we side-load the image into each node's
#               containerd. Needs Docker on the host, nothing on the nodes.
#
# Mode 2 is the fallback that always works, including on an air-gapped lab. It is
# also exactly how you would seed a real disconnected cluster, so it is worth
# knowing regardless.
#
# ARCHITECTURE (this is the one that bites, and it bites silently):
# the published ghcr package is amd64-only. On an Apple Silicon Mac the lab VMs
# are arm64, so a successful `crictl pull` still produces Pods that die with
#
#     exec /entrypoint.sh: exec format error
#
# CrashLoopBackOff, no mention of architecture anywhere in `describe pod`. So the
# pull path below is not trusted on its say-so -- it checks the pulled image's
# architecture against the node's and falls through to a local build if they
# disagree. Verified against the lab on 2026-09-06: the published v1 reported
# "architecture": "amd64" on arm64 nodes and every Pod crashed.
#================================================================
set -euo pipefail

# The name the course demos and manifests use. Keep these in step -- an image
# built under a different tag is an image the Deployments will never look at.
IMAGE="${GLOBO_IMAGE:-ghcr.io/timothywarner-org/globo-shop:v1}"
NODES=("control1" "worker1" "worker2")
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Talk to the VMs through the ssh config Vagrant generates. `ssh vagrant@worker1`
# only works if that name happens to resolve on your host, which on macOS it does
# not -- the VMs are reachable through per-machine ports, not by hostname.
SSH_CFG="${CKA_SSH_CONFIG:-$HERE/../../../cka-lab/.vagrant/cka-ssh-config}"
LAB_DIR="$(cd "$HERE/../../../cka-lab" 2>/dev/null && pwd || true)"
if [ ! -s "$SSH_CFG" ] && [ -n "$LAB_DIR" ]; then
    echo "==> Generating the Vagrant ssh config"
    ( cd "$LAB_DIR" && vagrant ssh-config > "$SSH_CFG" )
fi
[ -s "$SSH_CFG" ] || { echo "ERROR: no ssh config at $SSH_CFG -- are the lab VMs up?" >&2; exit 1; }

on()  { ssh -F "$SSH_CFG" "$1" "${@:2}"; }

# What are the nodes? docker and uname spell this differently (arm64 vs aarch64).
NODE_UNAME="$(on "${NODES[0]}" 'uname -m')"
case "$NODE_UNAME" in
    aarch64|arm64) NODE_ARCH=arm64; DOCKER_PLATFORM=linux/arm64 ;;
    x86_64|amd64)  NODE_ARCH=amd64; DOCKER_PLATFORM=linux/amd64 ;;
    *) echo "ERROR: unrecognised node architecture '$NODE_UNAME'" >&2; exit 1 ;;
esac
echo "==> Lab nodes are ${NODE_ARCH} (uname reports ${NODE_UNAME})"

#---------------------------------------------------------------
# 1. PULL -- and verify the architecture rather than trusting exit 0
#---------------------------------------------------------------
echo "==> Trying the easy path first: can the nodes pull ${IMAGE} themselves?"
if on "${NODES[0]}" "sudo crictl pull ${IMAGE}" >/dev/null 2>&1; then
    pulled_arch="$(on "${NODES[0]}" "sudo crictl inspecti ${IMAGE}" \
                   | sed -n 's/.*\"architecture\": *\"\([^\"]*\)\".*/\1/p' | head -1)"
    if [ "$pulled_arch" = "$NODE_ARCH" ]; then
        echo "    Yes, and it is ${pulled_arch}. Pulling on every node."
        for n in "${NODES[@]}"; do
            on "$n" "sudo crictl pull ${IMAGE}" >/dev/null 2>&1
            echo "    [OK] ${n}"
        done
        echo "==> Done. The nodes pulled the image from the registry."
        exit 0
    fi
    echo "    Pulled, but it is '${pulled_arch}' and these nodes are '${NODE_ARCH}'."
    echo "    Using it would CrashLoopBackOff with 'exec format error'. Building instead."
else
    echo "    No -- the registry is unreachable or the package is private."
fi

#---------------------------------------------------------------
# 2. BUILD for the node's architecture and side-load
#---------------------------------------------------------------
echo "==> Falling back: build locally for ${DOCKER_PLATFORM} and side-load into containerd."

command -v docker >/dev/null 2>&1 || {
    echo "ERROR: Docker is required for the build fallback. Install Docker and re-run." >&2
    exit 1
}

echo "--> Building ${IMAGE} (${DOCKER_PLATFORM})"
docker build --platform "$DOCKER_PLATFORM" --build-arg APP_VERSION=v1 -t "${IMAGE}" "${HERE}"

TAR="$(mktemp -t globo-shop-XXXXXX.tar)"
# Clean up the tarball even if a node transfer fails partway through.
trap 'rm -f "${TAR}"' EXIT

echo "--> Exporting to ${TAR}"
docker save "${IMAGE}" -o "${TAR}"

for n in "${NODES[@]}"; do
    echo "--> Loading onto ${n}"
    scp -q -F "$SSH_CFG" "${TAR}" "${n}:/tmp/globo.tar"
    # -n k8s.io is the containerd NAMESPACE Kubernetes reads from. Import into the
    # default containerd namespace instead and the kubelet will never find the image.
    on "$n" "sudo ctr -n k8s.io images import /tmp/globo.tar >/dev/null && rm -f /tmp/globo.tar"
    # Assert what actually landed: that the tag is visible to the kubelet AND that
    # it is the right architecture. A stale amd64 layer under the same tag would
    # otherwise pass a bare `grep globo-shop`.
    got="$(on "$n" "sudo crictl inspecti ${IMAGE}" \
           | sed -n 's/.*\"architecture\": *\"\([^\"]*\)\".*/\1/p' | head -1)"
    [ "$got" = "$NODE_ARCH" ] \
        && echo "    [OK] ${n} (${got})" \
        || { echo "    [FAIL] ${n} -- image reports '${got}', expected '${NODE_ARCH}'" >&2; exit 1; }
done

echo "==> Done. Every node has the image."
echo "    Course 7 Module 1 demos:  course-07-services-ingress-gateway/m01-service-types/"
echo "    Course 2 dev/prod overlays:"
echo "      kubectl apply -f manifests/environments.yaml"
echo "      kubectl apply -k manifests/overlays/dev"
echo "      kubectl apply -k manifests/overlays/prod"
