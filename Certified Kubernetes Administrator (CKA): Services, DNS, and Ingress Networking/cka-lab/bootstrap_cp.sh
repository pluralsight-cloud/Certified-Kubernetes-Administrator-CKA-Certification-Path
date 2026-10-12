#!/bin/bash

set -euo pipefail

#================================================================
# CNI choice - Calico via the Tigera operator (pinned)
#
# This lab standardized on Calico in Course 2 Module 3, and every
# recorded module since assumes it. Calico is also the realistic
# choice: NetworkPolicy actually enforces, which Course 8 needs.
#
# Pod CIDR is 192.168.0.0/16 because that is what Calico's default
# Installation CR ships with. C02 M03 proves that alignment on
# camera, so changing it here would silently contradict a recorded
# module. If you swap in another CNI, change POD_CIDR to match that
# CNI's expected range (Flannel: 10.244.0.0/16, Cilium: configurable).
#
# CALICO_VERSION is pinned to a release tag - NOT 'master' - so
# re-provisioning a year from now installs the same manifests you
# taught against. Bump deliberately, not accidentally.
#
# NOTE: the Course 4 Initialize-C04M0*Lab.ps1 scripts do their own
# bootstrap and do not call this file. Keep the kubeadm flags and the
# pinned Calico version here in sync with those scripts.
#================================================================
CALICO_VERSION="v3.29.1"
POD_CIDR="192.168.0.0/16"

# The network every lab node is addressed on: control1 .10, worker1 .11, .12.
LAB_CIDR="192.168.50.0/24"
LAB_PREFIX="192.168.50."

# Detect this node's address ON THE LAB NETWORK.
#
# `hostname -I | awk '{print $1}'` was correct on Hyper-V, where the VM has a
# single NIC. On VMware (the macOS path) there are two -- a NAT interface for
# internet access plus the host-only lab network -- and the NAT address often
# sorts first. Advertising the API server there would leave it unreachable from
# the host. Match the lab prefix, and fall back to the old expression so a
# single-NIC node still behaves exactly as before.
CP_IP=$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 \
        | grep -m1 "^${LAB_PREFIX}" || true)
CP_IP="${CP_IP:-$(hostname -I | awk '{print $1}')}"
echo "Control plane IP detected: $CP_IP"
echo "Workers will need this IP to join the cluster."
echo ""

echo "Initializing control plane..."
sudo kubeadm init \
  --apiserver-advertise-address="$CP_IP" \
  --pod-network-cidr="$POD_CIDR"

echo "Setting up kubeconfig..."
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $USER:$USER $HOME/.kube/config

echo "Installing CNI (Calico ${CALICO_VERSION} via Tigera operator)..."
# Two manifests, in order: the operator, then the Installation CR it watches.
#
# `apply --server-side`, not `create`. With `create`, a second run dies on
# "AlreadyExists" and, because of `set -e`, takes the whole script with it --
# so a bootstrap that failed halfway through (a flaky pull, an interrupted run)
# could never be resumed, only destroyed and rebuilt. Server-side apply also
# sidesteps the annotation-size limit that client-side apply hits on Calico's
# larger CRDs.
kubectl apply --server-side --force-conflicts -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"
kubectl apply --server-side --force-conflicts -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml"

# Calico's node-address autodetection carries the same two-NIC ambiguity as
# CP_IP above: the default "first found" method can latch onto the VMware NAT
# interface, and then every node reports the SAME 172.16.x address as its BGP
# endpoint -- pods come up, cross-node traffic does not. Constrain it to the lab
# CIDR. On a single-NIC Hyper-V node this picks the address it would have picked
# anyway, so the recorded behaviour is unchanged.
#
# The retry loop is because the operator has to register the Installation CRD
# before the object is patchable; it exists within a few seconds.
echo "Pinning Calico node-address autodetection to ${LAB_CIDR}..."
for i in $(seq 1 30); do
  if kubectl patch installation default --type=merge \
      -p "{\"spec\":{\"calicoNetwork\":{\"nodeAddressAutodetectionV4\":{\"cidrs\":[\"${LAB_CIDR}\"]}}}}" >/dev/null 2>&1; then
    echo "  [OK] nodeAddressAutodetectionV4 = ${LAB_CIDR}"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "  WARN: could not patch installation/default after 60s."
    echo "        Check: kubectl get installation default -o yaml"
  fi
  sleep 2
done

echo ""
echo "Waiting for Calico to come up (calico-system/calico-node)..."
kubectl -n calico-system rollout status ds/calico-node --timeout=180s || \
  echo "WARN: calico-node not ready yet. Check 'kubectl -n calico-system get pods'."

echo ""
echo "Get join command (copy this to each worker):"
kubeadm token create --print-join-command
