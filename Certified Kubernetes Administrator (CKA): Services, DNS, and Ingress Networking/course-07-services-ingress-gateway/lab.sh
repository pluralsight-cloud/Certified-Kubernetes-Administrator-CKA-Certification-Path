#!/usr/bin/env bash
#================================================================
# Course 7 lab harness -- Services, DNS, and Ingress Networking.
#
# Lives at the COURSE level, not in a module folder, because all three modules
# share one stack: M01's Services are what M02's Ingress routes to, and what
# M03's HTTPRoutes route to. Splitting it three ways would mean three copies of
# the same Traefik install.
#
#   ./lab.sh              gatewayapi + traefik + apps + verify
#   ./lab.sh gatewayapi   install the Gateway API CRDs
#   ./lab.sh traefik      install Traefik via Helm (Ingress + Gateway provider)
#   ./lab.sh apps         deploy the Globomantics backends (catalog/portal/api)
#   ./lab.sh verify       assert the whole stack is actually serving
#   ./lab.sh reset        remove everything this script created
#
# Re-runnable at any point: Helm installs are `upgrade --install`, manifests are
# `apply`, and every delete carries --ignore-not-found and an explicit timeout.
#
# Prereqs: the three-node lab cluster (src/cka-lab -- TUTORIAL-MACOS.md on a Mac,
# TUTORIAL-HYPERV.md on Windows) plus kubectl and helm on your workstation.
#================================================================
set -euo pipefail

# --- Pins -------------------------------------------------------------------
# Gateway API CRD release.
#
# The course outline pins v1.2.0. That version DOES NOT WORK with Traefik 3.7 --
# verified on the lab cluster, not guessed. Traefik's Gateway provider watches
# TLSRoute and BackendTLSPolicy at v1; the v1.2.0 standard channel ships neither,
# so its informers never sync and the provider stalls silently:
#
#   Failed to watch err="failed to list *v1.TLSRoute: the server could not find
#   the requested resource (get tlsroutes.gateway.networking.k8s.io)"
#
# The visible symptom is a GatewayClass stuck at Accepted=Unknown and a Gateway
# stuck Pending, with nothing in the events to explain it. Ingress keeps working,
# which makes it look like only Module 3 is broken.
#
# v1.6.1 standard is the first release serving BOTH kinds at v1 (v1.4.0 standard
# added BackendTLSPolicy but not TLSRoute). Still the standard channel, so the
# "install the standard-channel CRDs" narrative is intact.
GWAPI_VERSION="${GWAPI_VERSION:-v1.6.1}"

# Traefik Helm chart. Pinned so a re-record months from now installs what you
# taught against. chart 41.4.0 == Traefik v3.7.12.
TRAEFIK_CHART_VERSION="${TRAEFIK_CHART_VERSION:-41.4.0}"
TRAEFIK_NS="traefik"

# The lab has no cloud provider, so a LoadBalancer Service would sit <pending>
# forever and nothing would be reachable. Traefik is exposed as a NodePort on
# fixed ports instead, so the host can browse http://<any node IP>:30080.
# (That a LoadBalancer stays <pending> here is itself a Module 1 teaching beat --
# it is deliberate, not a defect.)
WEB_NODEPORT=30080
WEBSECURE_NODEPORT=30443
NODE_IP="${CKA_NODE_IP:-192.168.50.11}"

# Everything this script creates carries this label, so reset is surgical --
# it never touches anything you created by hand in the same namespace.
LABEL="app.kubernetes.io/part-of=globo-c07"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# Course 4 standing convention, kept here: always show which cluster you are
# about to change. On the exam every task starts with a context switch.
show_context() {
  command -v kubectl >/dev/null 2>&1 || die "kubectl not found"
  say "Cluster context"
  kubectl config current-context || die "No current context. export KUBECONFIG=~/.kube/cka-config"
  kubectl get nodes -o wide 2>/dev/null | head -5 || die "Cannot reach the API server"
}

#---------------------------------------------------------------
cmd_gatewayapi() {
  say "Installing Gateway API CRDs ${GWAPI_VERSION} (standard channel)"
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWAPI_VERSION}/standard-install.yaml"
  # Assert rather than assume: a partial apply still exits 0 often enough.
  for crd in gatewayclasses gateways httproutes; do
    kubectl get crd "${crd}.gateway.networking.k8s.io" >/dev/null \
      || die "CRD ${crd}.gateway.networking.k8s.io missing after install"
    info "[OK] ${crd}.gateway.networking.k8s.io"
  done
}

cmd_traefik() {
  command -v helm >/dev/null 2>&1 || die "helm not found -- brew install helm"

  # Traefik's Gateway provider watches Gateway API resources at startup, so the
  # CRDs have to exist first or the controller logs errors and never serves.
  kubectl get crd gatewayclasses.gateway.networking.k8s.io >/dev/null 2>&1 \
    || die "Gateway API CRDs missing. Run: ./lab.sh gatewayapi"

  say "Installing Traefik (chart ${TRAEFIK_CHART_VERSION}) into namespace ${TRAEFIK_NS}"
  helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
  helm repo update traefik >/dev/null

  # gateway.enabled / gatewayClass.enabled are turned OFF on purpose: the chart
  # would otherwise ship a ready-made GatewayClass and Gateway, and Module 3's
  # whole point is that the learner creates those two objects themselves.
  #
  # ports.web.port=80 / ports.websecure.port=443 matter more than they look.
  # Traefik matches a Gateway LISTENER to an entryPoint BY PORT. The chart's
  # default entryPoints are :8000 and :8443, so a Gateway with the listener
  # everyone actually writes --
  #
  #     listeners: [{name: http, protocol: HTTP, port: 80}]
  #
  # -- is rejected with "no matching entryPoint for port 80 and protocol HTTP".
  # Teaching learners to write port 8000 to suit one controller's chart defaults
  # would be teaching them the wrong thing for the exam, so move the entryPoint
  # instead. Binding 80 as the chart's non-root UID 65532 needs NET_BIND_SERVICE,
  # hence the capability. Everything else in the pod's securityContext (drop ALL,
  # no privilege escalation, read-only root) is untouched.
  helm upgrade --install traefik traefik/traefik \
    --version "$TRAEFIK_CHART_VERSION" \
    --namespace "$TRAEFIK_NS" --create-namespace \
    --set service.spec.type=NodePort \
    --set ports.web.nodePort="$WEB_NODEPORT" \
    --set ports.websecure.nodePort="$WEBSECURE_NODEPORT" \
    --set ports.web.port=80 \
    --set ports.websecure.port=443 \
    --set "securityContext.capabilities.add={NET_BIND_SERVICE}" \
    --set providers.kubernetesIngress.enabled=true \
    --set providers.kubernetesGateway.enabled=true \
    --set gateway.enabled=false \
    --set gatewayClass.enabled=false \
    --wait --timeout 5m

  kubectl -n "$TRAEFIK_NS" rollout status deploy/traefik --timeout=180s
  info "[OK] Traefik serving on http://${NODE_IP}:${WEB_NODEPORT} (HTTP) and :${WEBSECURE_NODEPORT} (HTTPS)"
}

# One backend, rendered three ways. Each Pod serves a page that names itself, so
# a routing rule that sends traffic to the wrong Service is visible on screen
# instead of hiding behind an identical nginx welcome page.
app_manifest() {
  local name="$1" title="$2" replicas="$3"
  cat <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${name}-page
  labels: { ${LABEL%%=*}: ${LABEL#*=} }
data:
  index.html: |
    <!doctype html>
    <title>${title}</title>
    <h1>${title}</h1>
    <p>Globomantics -- CKA Course 7</p>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${name}
  labels: { app: ${name}, ${LABEL%%=*}: ${LABEL#*=} }
spec:
  replicas: ${replicas}
  selector:
    matchLabels: { app: ${name} }
  template:
    metadata:
      labels: { app: ${name}, ${LABEL%%=*}: ${LABEL#*=} }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
          volumeMounts:
            - name: page
              mountPath: /usr/share/nginx/html
          readinessProbe:
            httpGet: { path: /, port: 80 }
            initialDelaySeconds: 2
      volumes:
        - name: page
          configMap: { name: ${name}-page }
---
apiVersion: v1
kind: Service
metadata:
  name: ${name}
  labels: { app: ${name}, ${LABEL%%=*}: ${LABEL#*=} }
spec:
  type: ClusterIP
  selector: { app: ${name} }
  ports:
    - port: 80
      targetPort: 80
YAML
}

cmd_apps() {
  say "Deploying the Globomantics backends into namespace default"
  info "default namespace on purpose -- the demos curl catalog.default.svc.cluster.local"
  {
    app_manifest catalog    "Product catalog (v1)"      3
    echo "---"
    app_manifest catalog-v2 "Product catalog (v2)"      1
    echo "---"
    app_manifest portal     "Customer portal"           1
    echo "---"
    app_manifest api        "Partner integration API"   1
  } | kubectl apply -f -

  for d in catalog catalog-v2 portal api; do
    kubectl rollout status "deploy/$d" --timeout=120s
  done
}

cmd_verify() {
  say "Verifying the Course 7 stack"
  local fail=0

  # Gateway API CRDs
  for crd in gatewayclasses gateways httproutes; do
    if kubectl get crd "${crd}.gateway.networking.k8s.io" >/dev/null 2>&1; then
      info "[OK]   CRD ${crd}"
    else
      info "[FAIL] CRD ${crd} missing"; fail=1
    fi
  done

  # Traefik
  if kubectl -n "$TRAEFIK_NS" get deploy traefik >/dev/null 2>&1; then
    local ready
    ready="$(kubectl -n "$TRAEFIK_NS" get deploy traefik -o jsonpath='{.status.readyReplicas}')"
    [ "${ready:-0}" -ge 1 ] && info "[OK]   Traefik ready (${ready} replica)" \
                            || { info "[FAIL] Traefik has no ready replica"; fail=1; }
  else
    info "[FAIL] Traefik deployment not found"; fail=1
  fi

  # Backends. Ask for the full endpoint list and require exit 0 -- a `grep` that
  # finds nothing is indistinguishable from a command that failed outright.
  for d in catalog catalog-v2 portal api; do
    local eps
    if eps="$(kubectl get endpointslice -l "kubernetes.io/service-name=$d" \
              -o jsonpath='{.items[*].endpoints[*].addresses[*]}' 2>/dev/null)" && [ -n "$eps" ]; then
      info "[OK]   $d endpoints: $(printf '%s' "$eps" | wc -w | tr -d ' ')"
    else
      info "[FAIL] $d has no endpoints"; fail=1
    fi
  done

  # The property the whole course rests on: the node's real IP is reachable from
  # this workstation. Traefik answers 404 when no route matches -- that is a
  # PASS, it proves the request reached the controller.
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://${NODE_IP}:${WEB_NODEPORT}/" || true)"
  if [ "$code" != "000" ] && [ -n "$code" ]; then
    info "[OK]   http://${NODE_IP}:${WEB_NODEPORT}/ answered HTTP ${code} (404 with no routes defined is correct)"
  else
    info "[FAIL] no answer from http://${NODE_IP}:${WEB_NODEPORT}/ -- check the node IP and the NodePort"; fail=1
  fi

  [ "$fail" -eq 0 ] && say "Course 7 stack OK" || die "Course 7 stack incomplete (see [FAIL] lines)"
}

cmd_reset() {
  say "Removing everything ./lab.sh created"
  # Label-scoped so a hand-made object in the same namespace survives.
  kubectl delete deploy,svc,configmap,ingress -l "$LABEL" --ignore-not-found --timeout=120s
  # Gateway/HTTPRoute/GatewayClass objects go with their CRDs a few lines down --
  # deleting a CRD deletes every instance of it, so listing them here would be
  # redundant work that can only produce confusing errors.
  helm uninstall traefik -n "$TRAEFIK_NS" --timeout 5m 2>/dev/null || info "traefik release already gone"
  kubectl delete namespace "$TRAEFIK_NS" --ignore-not-found --timeout=120s
  kubectl delete -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWAPI_VERSION}/standard-install.yaml" \
    --ignore-not-found --timeout=120s 2>/dev/null || true
  info "[OK] reset complete"
}

cmd_all() { show_context; cmd_gatewayapi; cmd_traefik; cmd_apps; cmd_verify; }

case "${1:-all}" in
  all|"")     cmd_all ;;
  gatewayapi) show_context; cmd_gatewayapi ;;
  traefik)    show_context; cmd_traefik ;;
  apps)       show_context; cmd_apps ;;
  verify)     cmd_verify ;;
  reset)      show_context; cmd_reset ;;
  -h|--help|help) sed -n '2,25p' "${BASH_SOURCE[0]}" ;;
  *)          die "Unknown subcommand '$1'. Try: ./lab.sh help" ;;
esac
