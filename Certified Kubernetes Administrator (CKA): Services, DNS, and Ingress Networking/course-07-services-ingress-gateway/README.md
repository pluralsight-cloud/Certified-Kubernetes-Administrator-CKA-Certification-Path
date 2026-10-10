# Course 7 -- Services, Ingress, and Gateway API

**Course 7 of 11**  |  **CKA domain:** Services & Networking (20%)  |  **Runtime:** ~90 min

Expose workloads: Service types, Ingress for HTTP routing, and the new Gateway API (GatewayClass, Gateway, HTTPRoute) added in the February 2025 curriculum.

---

## Modules

| # | Module | Exam objectives | Files |
| --- | --- | --- | --- |
| M01 | [Service Types](m01-service-types/README.md) | ClusterIP, NodePort, LoadBalancer, and how Services map to EndpointSlices. | Coming as recorded |
| M02 | [Ingress](m02-ingress/README.md) | Ingress resources, ingress controllers, and host/path routing rules. | Coming as recorded |
| M03 | [Gateway API](m03-gateway-api/README.md) | GatewayClass, Gateway, and HTTPRoute (new in Feb 2025; the successor to Ingress). | Coming as recorded |

---

## How to use this course

1. Open the module folder for the video you're watching; its **README** lists every file and maps it to the CKA exam objectives.
2. Spin up a cluster from [`cka-lab/`](../cka-lab/) and run the demos yourself -- [`TUTORIAL-HYPERV.md`](../cka-lab/TUTORIAL-HYPERV.md) on Windows, [`TUTORIAL-MACOS.md`](../cka-lab/TUTORIAL-MACOS.md) on a Mac.
3. Install this course's stack with [`lab.sh`](lab.sh): Gateway API CRDs, Traefik via Helm (it serves both the Ingress and the Gateway API demos), and the Globomantics `catalog` / `portal` / `api` backends. `./lab.sh verify` asserts the whole thing is serving.
4. Manifests target a standard cluster (1 control-plane + 2 workers) at Kubernetes **v1.35**.

| Command | What it does |
| --- | --- |
| `./lab.sh` | Everything below, then verify |
| `./lab.sh gatewayapi` | Gateway API CRDs (standard channel) |
| `./lab.sh traefik` | Traefik via Helm, exposed as a NodePort on `30080` / `30443` |
| `./lab.sh apps` | The three Globomantics backends, plus `catalog-v2` for traffic splitting |
| `./lab.sh verify` | Asserts CRDs, controller, endpoints, and host reachability |
| `./lab.sh reset` | Removes everything it created |

Note: `type: LoadBalancer` Services stay `<pending>` on this lab. That is correct -- there is no cloud provider, and Module 1 teaches exactly that.
