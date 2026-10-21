# Chaos Engineering Platform Architecture & System Design

## 1. Executive Summary

This document specifies the technical architecture, design patterns, fault injection mechanics, safety boundaries, and observability pipelines of the **Chaos Engineering Platform** deployed on Kubernetes using **Chaos Mesh**.

The platform is designed to shift reliability testing from reactive incident response to **proactive, automated, hypothesis-driven resilience discovery**. By systematically injecting pod disruptions, network degradation, storage latency, CPU/memory saturation, and API-level faults into a realistic microservices environment, the system exposes architectural weaknesses—such as cascading timeouts, missing circuit breakers, and unhandled dependency failures—before they impact end users.

---

## 2. Platform Architecture Overview

The platform comprises four discrete layers organized into isolated Kubernetes namespaces:

1. **Control Plane & Container Orchestration Layer (`kube-system`, `local-path-storage`)**: Provides the Kubernetes API, kubelet, CoreDNS, and CNI networking.
2. **Chaos Engineering Engine (`chaos-mesh`)**: Houses the Chaos Mesh Controller Manager, Chaos Daemons (DaemonSet with hostPID access for eBPF/tc/cgroup injection), and the Chaos Web Dashboard.
3. **Target Application Layer (`online-boutique`)**: A cloud-native 11-tier microservice architecture (Google Online Boutique) featuring gRPC and HTTP inter-service communication, in-memory caching (Redis), and an autonomous synthetic traffic generator.
4. **Observability & SLI Monitoring Stack (`monitoring`)**: Prometheus server scraping application endpoints, cAdvisor, and Chaos Mesh components, feeding a tailored Grafana Service-Level Indicator (SLI) dashboard.

### High-Level Architecture Diagram

```mermaid
flowchart TB
    subgraph Host["Host Environment (Developer / CI/CD)"]
        Browser["Operator / Web Browser"]
        CLI["Automation Scripts / submission.yml / kubectl"]
    end

    subgraph K8s["Kubernetes Cluster (Kind: chaos-cluster)"]
        subgraph IngressPorts["Exposed Port Forwards"]
            P30080["30080: Application Frontend"]
            P2333["2333: Chaos Mesh Dashboard"]
            P9090["9090: Prometheus UI"]
            P3000["3000: Grafana SLI Dashboard"]
        end

        subgraph CM_NS["Namespace: chaos-mesh"]
            CRDs["Chaos Mesh CRDs\n(PodChaos, NetworkChaos, IOChaos, StressChaos, HTTPChaos, Workflow, Schedule)"]
            CCM["Chaos Controller Manager\n(Validating Webhook & CRD Reconciler)"]
            CD["Chaos Daemon (DaemonSet)\n[tc / iptables / cgroup / eBPF / FUSE]"]
            CDB["Chaos Dashboard UI"]
        end

        subgraph APP_NS["Namespace: online-boutique (Target System)"]
            Frontend["Frontend (Go / HTTP :8080)"]
            LoadGen["Load Generator (Synthetic Traffic)"]
            CartSvc["Cart Service (gRPC)"]
            Redis["Redis Cart (In-Memory Cache /data)"]
            Catalog["Product Catalog Service (gRPC)"]
            Currency["Currency Service (Node.js)"]
            Payment["Payment Service (Node.js)"]
            Shipping["Shipping Service (Go)"]
            Checkout["Checkout Service (Go)"]
            Email["Email Service (Python)"]
            Recommend["Recommendation Service (Python)"]
            Ad["Ad Service (Java)"]

            LoadGen --> Frontend
            Frontend --> Catalog
            Frontend --> CartSvc
            Frontend --> Currency
            Frontend --> Recommend
            Frontend --> Checkout
            Frontend --> Shipping
            Frontend --> Ad
            CartSvc --> Redis
            Checkout --> Payment
            Checkout --> Email
            Checkout --> Shipping
        end

        subgraph MON_NS["Namespace: monitoring (Observability)"]
            Prom["Prometheus v2.54\n(TSDB & Metric Scraper)"]
            Grafana["Grafana v11.1\n(Golden Signals & Chaos SLI Dashboards)"]
            cAdvisor["Kubelet / cAdvisor\n(Resource Metrics)"]
            
            Prom --> cAdvisor
            Prom --> Frontend
            Prom --> CCM
            Prom --> CD
            Grafana --> Prom
        end
    end

    Browser --> P30080
    Browser --> P2333
    Browser --> P9090
    Browser --> P3000
    CLI --> CRDs

    P30080 --> Frontend
    P2333 --> CDB
    P9090 --> Prom
    P3000 --> Grafana

    CCM --> CRDs
    CCM --> CD
    CD -.->|Injects Failure| Frontend
    CD -.->|Injects Failure| CartSvc
    CD -.->|Injects Failure| Catalog
    CD -.->|Injects Failure| Redis
    CD -.->|Injects Failure| Checkout
```

---

## 3. Component Deep Dive & Interactions

### 3.1 Chaos Mesh Engine Architecture

Chaos Mesh operates as a cloud-native operator leveraging the Kubernetes Controller Pattern and Mutating/Validating Admission Webhooks:

```mermaid
sequenceDiagram
    autonumber
    participant Op as Chaos Workflow / Manifest
    participant K8s as Kubernetes API Server
    participant CCM as Chaos Controller Manager
    participant CD as Chaos Daemon (Node Host)
    participant Pod as Target Application Pod

    Op->>K8s: Apply Chaos CRD (e.g., NetworkChaos, PodChaos)
    K8s->>CCM: Admission Webhook validates Spec & Blast Radius
    K8s->>CCM: Event Reconcile Trigger
    CCM->>CCM: Evaluate Selectors (Namespace, Labels)
    CCM->>CD: gRPC Request (Container ID, PID, Fault Parameters)
    CD->>Pod: Inject Fault (Traffic Control / Signal / Cgroup / FUSE)
    Note over Pod: Target experiences latency, failure, or throttling
    CCM->>K8s: Update CRD Status (Injected / Duration Timer)
    Note over CCM: Experiment Duration Expires
    CCM->>CD: gRPC Request (Recover Fault)
    CD->>Pod: Remove iptables rules / tc qdisc / reset cgroups
    CCM->>K8s: Status: AllRecovered
```

1. **Chaos Controller Manager**:
   - Reconciles custom resources (`PodChaos`, `NetworkChaos`, `IOChaos`, `StressChaos`, `HTTPChaos`, `Workflow`, `Schedule`).
   - Translates high-level declarative intent into low-level runtime instructions.
   - Schedules and sequences complex multi-stage workflows.
2. **Chaos Daemon**:
   - Deployed as a `DaemonSet` with privileged permissions and host namespace access (`hostPID: true`, `hostNetwork: false`).
   - Communicates with the node container runtime socket (`/run/containerd/containerd.sock`).
   - Uses Linux kernel facilities to inject faults:
     - **NetworkChaos**: Manipulates kernel packet scheduling queues using `tc` (Traffic Control) and `netem` (Network Emulation), or manipulates routing via `iptables`.
     - **PodChaos**: Sends `SIGKILL`, `SIGTERM`, or attaches pause containers via container runtime APIs.
     - **StressChaos**: Invokes `stress-ng` in the target cgroup subsystem (memory and CPU controllers) to exhaust resource allocations.
     - **IOChaos**: Mounts dynamic FUSE (Filesystem in Userspace) file systems or attaches eBPF kprobes to inject latency and error codes into file descriptor operations (`read`, `write`, `sync`).
     - **HTTPChaos**: Proxies or patches HTTP packets via `tproxy` or sidecar interception to modify status codes, abort connections, or inject synthetic response delays.

---

## 4. Blast Radius Containment & Safety Controls

Chaos experiments have the potential to destabilize unexpected system components if unconstrained. To enforce strict **blast radius boundaries**, the platform incorporates multiple defensive layers:

```mermaid
flowchart LR
    subgraph SafeCluster["Cluster Blast Radius Guardrails"]
        direction TB
        subgraph Excluded["PROTECTED NAMESPACES (Zero-Chaos Zone)"]
            KS["kube-system\n(CoreDNS, API Server, etcd)"]
            MON["monitoring\n(Prometheus, Grafana)"]
            CMS["chaos-mesh\n(Controllers, Daemons)"]
        end
        
        subgraph TargetZone["CONTROLLED BLAST RADIUS"]
            direction TB
            subgraph TargetNS["Namespace: online-boutique"]
                FE["app: frontend"]
                CS["app: cartservice"]
                RC["app: redis-cart"]
                PC["app: productcatalogservice"]
            end
        end
    end

    Guard["Safety Check:\n1. Namespace in [online-boutique]\n2. Label Selector strictly matched\n3. Pre-flight Steady-State Passed\n4. Finite Durations (<=60s)"]
    Guard --> TargetZone
```

### Safety Controls Implemented:

| Safety Mechanism | Implementation Details | Purpose |
| :--- | :--- | :--- |
| **Namespace Isolation** | Explicit `namespaces: [online-boutique]` defined in all experiment specs | Prohibits failure injection into `kube-system`, `monitoring`, or `default`. |
| **Granular Label Selectors** | Exact match on `labelSelectors: { app: <service-name> }` | Guarantees experiments isolate one microservice at a time (e.g. only `frontend` or only `redis-cart`). |
| **Strict Mode & Scope Limits** | `mode: one` or `fixed: 1` utilized for destructive tests | Prevents simultaneous complete cluster outages by ensuring at least one replica survives where applicable. |
| **Mandatory Durations** | Explicit `duration` parameter (30s to 60s) on all experiments | Prevents orphaned or permanent faults in the event of an orchestrator disconnect. |
| **Concurrency Safeguards** | `concurrencyPolicy: Forbid` in `Schedule` resources | Forbids overlapping scheduled tests, preventing compounding runaway failures. |
| **Pre-flight Health Checks** | Automated synthetic probes verifying HTTP 200 and latency baseline (< 500ms) before injection | Aborts chaos test initiation if the system is already degraded. |

---

## 5. Observability & Telemetry Architecture

To uphold the core chaos engineering principle of **measuring steady state**, the observability stack captures metrics from the application, infrastructure, and chaos engine simultaneously.

### Metrics Pipeline Flow

```mermaid
flowchart LR
    AppPods["Online Boutique Pods\n(:8080 / :7070)"] -->|Metrics / HTTP Status| Prom["Prometheus (port 9090)"]
    Kubelet["Kubelet / cAdvisor\n(CPU, Memory, Restarts)"] -->|Container Metrics| Prom
    ChaosEngine["Chaos Controller & Daemon\n(:1022 / :31767)"] -->|Experiment Telemetry| Prom
    
    Prom -->|PromQL| Grafana["Grafana (port 3000)"]
    
    subgraph Dashboard["SLI Dashboard Panels"]
        D1["Application Availability Gauge"]
        D2["p50 / p90 / p99 Latency Curves"]
        D3["HTTP & Network Error Rate %"]
        D4["CPU / Memory Saturation"]
        D5["Pod Restarts Counter"]
    end
    Grafana --> Dashboard
```

### Golden Signals & Service-Level Indicators (SLIs)

1. **Latency**:
   - Metric: `histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[1m])) by (le)) * 1000`
   - Steady-State Baseline: p50 < 25ms, p99 < 80ms.
2. **Traffic**:
   - Metric: `sum(rate(container_network_receive_packets_total{namespace="online-boutique"}[1m])) by (pod)`
   - Baseline: Continuous synthetic workload generated by `loadgenerator`.
3. **Errors**:
   - Metric: `(sum(rate(container_network_receive_errors_total{namespace="online-boutique"}[1m])) / sum(rate(container_network_receive_packets_total{namespace="online-boutique"}[1m]))) * 100`
   - Baseline: 0.0% error rate during steady state.
4. **Saturation**:
   - Metric: `sum(rate(container_cpu_usage_seconds_total{namespace="online-boutique"}[1m])) by (pod)` and `container_memory_working_set_bytes`
   - Baseline: Average CPU utilization < 25% across all microservices.

---

## 6. Multi-Stage Chaos Workflow Topology

The cascading failure workflow (`chaos/workflows/cascading-failure-workflow.yaml`) simulates a progressive real-world outage combining upstream network degradation, compute saturation, pod crashes, and API failures:

```mermaid
flowchart TD
    Start(["Workflow Triggered"]) --> Step1["Phase 1: Serial Step 1\nNetworkChaos: 250ms Delay on Product Catalog (45s)"]
    Step1 --> Step2{"Phase 2: Parallel Block\nSimultaneous Dual-Failure (45s)"}
    
    subgraph ParallelFailures["Parallel Fault Injection"]
        Step2A["Branch A: PodChaos\nPod-Kill on Frontend"]
        Step2B["Branch B: StressChaos\nCPU Saturation (80% load) on Frontend"]
    end
    
    Step2 --> Step2A
    Step2 --> Step2B
    Step2A --> Sync["Synchronize Parallel Branches"]
    Step2B --> Sync
    
    Sync --> Step3["Phase 3: Serial Step 3\nHTTPChaos: Replace /cart/checkout with HTTP 500 (45s)"]
    Step3 --> Verify["Automated Recovery & Steady-State Verification"]
    Verify --> Done(["Workflow Complete"])
```

This sequence tests the application's ability to withstand compounding stress:
- Can the frontend gracefully render partial catalogs when the catalog is delayed?
- Does Kubernetes replica rescheduling maintain uptime when a saturated frontend pod is killed?
- Does the client interface handle payment/checkout failures gracefully without hanging or double-charging?

---

## 7. Network and Port Allocation

| Service | Cluster Type | Cluster Port | NodePort | Host Port | Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `frontend-external` | NodePort | 80 / 8080 | 30080 | `30080` | Online Boutique E-Commerce Web Store |
| `chaos-dashboard` | NodePort | 2333 | 32333 | `2333` | Chaos Mesh Experiment Management UI |
| `prometheus` | NodePort | 9090 | 30090 | `9090` | Prometheus Metrics & PromQL Console |
| `grafana` | NodePort | 3000 | 30300 | `3000` | Grafana SLI & Resilience Dashboards |

All host ports are permanently bound via Kind's `extraPortMappings`, ensuring local access without requiring manual `kubectl port-forward` background processes.
