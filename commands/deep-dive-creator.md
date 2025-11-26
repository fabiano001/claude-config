---
name: Deep Dive Creator
description: Generate comprehensive technical deep dive documentation for a software project. Takes project name and main feature flows (required), plus optional codebase references (frontend/backend components) and project context (tech stack, domain, stage). Produces a structured 9-section Markdown document covering architecture, data & integrations, security, reliability, implementation highlights, testing, operational readiness, and technical roadmap. Tailored for executive and senior engineering audience (CTO, principals, security directors).
---

You are helping me write a TECHNICAL DEEP DIVE document for a software project.

### REQUIRED INPUTS

Project name: [PROJECT NAME]

Features to cover (main flows for this deep dive):
- [Flow 1: short description]
- [Flow 2: short description]
- [Flow 3: short description]

Secondary/edge flows (optional):
- [Flow/feature A: short description]
- [Flow/feature B: short description]

Use these features/flows as the backbone for how you explain the architecture, data, and integrations.

---

### OPTIONAL INPUTS – Codebase Reference (you are already inside the repo)

Use this section to point at the most relevant parts of the code so you can really understand how this project is implemented.
These are *signposts* only; you are expected to explore nearby files and follow references/imports.

**Can include:**
- File paths and directory patterns (e.g., `src/features/auth/*`, `services/payment.ts`)
- Component names (e.g., `LoginForm`, `PaymentService`, `useAuth`)
- Pull Request URLs (e.g., `https://github.com/org/repo/pull/123`) - Review PR diffs, discussions, and implementation details to understand feature context and technical decisions

Frontend components involved:
- Pages/routes: [e.g., src/pages/LoanApplication.tsx, src/routes/apply/*]
- Feature components: [e.g., src/features/prequal/PrequalForm.tsx]
- Shared UI/utils: [e.g., src/components/forms/*, src/hooks/useAuth.ts]

Backend components involved:
- Services / modules: [e.g., src/services/prequalService.ts, src/modules/loans/*]
- API handlers / controllers: [e.g., src/routes/prequal.ts, src/controllers/loanController.ts]
- Jobs / workers / event handlers: [e.g., src/workers/PrequalDecisionWorker.ts]

Shared & configuration:
- Shared domain models: [e.g., src/domain/LoanApplication.ts]
- Config / feature flags: [e.g., src/config/featureFlags.ts, env var names]
- Any relevant infra-as-code / deployment configs: [e.g., infra/prequal-service/*]

When describing architecture and flows, prefer using these real component names and explore related files to deepen your understanding.

---

### OPTIONAL INPUTS – Project Context

Use this context to shape the content and fill gaps that are not obvious from code alone:

High-level description: [1–2 SENTENCES]
Tech stack: [FRONTEND / BACKEND / DATA / INFRA]
Domain: [e.g., lending funnel, payments, marketplace, internal tooling]
Stage: [e.g., design, MVP in prod, GA, in migration]
Anything special to highlight: [e.g., major refactor, critical integration, security-sensitive]

---

### Audience
- CTO, principal engineers, security director, senior product (CPO, PO)
- Assume they are technically strong and time-constrained
- They want clarity on architecture, risks, and readiness, not marketing

---

### Workflow

Follow this sequence before writing the documentation:

1. **Collect inputs** - Gather all required inputs (project name, features to cover) and optional inputs (codebase references, project context) from the user.

2. **Explore codebase** - Use the provided codebase references as signposts. Explore nearby files, follow imports/references, and build a solid understanding of:
   - How the main features/flows are implemented
   - **Trace end-to-end flows**: For each feature, read the code from frontend to backend following the complete request path:
     * Start at the UI component/page that triggers the action
     * Follow API calls to backend endpoints/controllers
     * Trace through service layers, business logic, and data access layers
     * Identify database queries, ORM operations, or data store interactions
     * Track any cloud function invocations (AWS Lambda, GCP Cloud Functions, etc.)
     * Follow event emissions, queue messages, or async processing
     * Understand response handling and error flows back to the frontend
   - Key components, services, and their responsibilities
   - Data models and integrations
   - Architecture patterns and technical decisions
   - **IMPORTANT**: Understanding the full request/response cycle for each main feature is critical for accurately describing architecture, data flow, and integrations

3. **Generate outline & plan** - Before writing the full document, produce a concise outline showing:
   - What you understand about the project (1-2 paragraph summary)
   - Which codebase areas you've explored
   - **End-to-end flow summary**: For each main feature, briefly describe the request path you traced (e.g., "User clicks submit → POST /api/loans → LoanService.create() → PostgreSQL loans table → SQS notification → EmailWorker")
   - Key technical themes you plan to cover in each section
   - Any gaps or unclear areas flagged as `TODO: clarify X`

4. **Ask clarifying questions** - If anything is ambiguous or missing:
   - Ask specific, targeted questions to fill knowledge gaps
   - Request additional codebase pointers if needed
   - Clarify scope or technical details that aren't clear from code alone

5. **Plan review loop** - Present the outline and ask: **"What changes would you like to make to this outline? Reply with edits, or say 'no' / 'no further changes' to proceed with writing the full document."**
   - Apply requested edits and re-present the updated outline
   - Repeat until the user confirms **"no" / "no further changes"**

6. **Write the full document** - Only after the user approves the outline, proceed to write the complete deep dive document following the sections below.

---

### Task
Create the **initial draft** of a technical deep dive document in **Markdown**, using the section structure below.

For each section:
- Use **short paragraphs + bullet points**
- Keep language clear, concise, and specific
- Prefer concrete examples over vague phrases
- Reference **actual components/services/modules/routes** from the codebase where possible
- Tie explanations back to the **Features to cover**
- If information is missing from the inputs or unclear from code, add a bullet like: `TODO: clarify X`

### Sections to produce

1. ## Project Overview (Tech TL;DR)
   - One or two sentences on what the system does
   - Scope in technical terms (e.g., "new Node.js API + React front-end + integration with X and Y")
   - Primary technical objectives (e.g., reduce latency, centralize auth, improve observability)
   - Brief summary of the main features/flows covered in this deep dive (from "Features to cover")

2. ## Architecture Overview
   - High-level description of components and responsibilities (using real component/service names)
   - How it fits into the existing ecosystem (upstream/downstream systems)
   - A textual description of an architecture diagram (e.g., "Browser → API Gateway → Service A → DB1; events via Kafka to Service B")
   - For each key feature/flow, which components are involved

3. ## Data & Integrations
   - Main data models / core entities and their relationships
   - Data flow for the primary feature(s) (step-by-step, request → processing → persistence → external systems)
   - Critical integrations (internal services, external vendors, queues/events) and how failures/retries are handled
   - Any important schemas or contracts (mention file/module names if known)

4. ## Security & Access Control
   - AuthN/AuthZ approach (protocols, IdP, major libraries)
   - Role/permission model and where checks are enforced (e.g., API gateway, backend services, UI guards)
   - Handling of sensitive data (encryption, secrets management, PII/PCI/PHI considerations)
   - Any notable security tradeoffs, known gaps, or open questions

5. ## Reliability, Scalability & Performance
   - Availability and performance goals (desired latency, throughput, error rates)
   - Scaling strategy (horizontal scaling, caching, queues, rate limiting, partitioning)
   - Resilience patterns (timeouts, retries with backoff, circuit breakers, idempotency)
   - Observability: key metrics, logs, traces, alerts (what we monitor and why, with concrete metric/log names where possible)

6. ## Implementation Highlights
   - 2–4 interesting or non-trivial technical decisions (patterns, algorithms, libraries, migrations)
   - Important tradeoffs (e.g., consistency vs availability, complexity vs speed of delivery)
   - Any notable refactors or strangler-pattern-style migrations
   - Pointers to key files/modules that illustrate these decisions

7. ## Testing & Quality
   - Types of tests used (unit, integration, contract, E2E) and their roles
   - How integrations are tested (mocking vs sandbox vs contract tests)
   - Tooling/automation (CI pipelines, static analysis, security scans, coverage thresholds)
   - Any gaps or TODOs in test coverage for the main features/flows

8. ## Operational Readiness
   - Deployment strategy (blue/green, canary, feature flags, rollback plan)
   - Environments and promotion flow (dev → staging → prod)
   - Runbooks / playbooks (how on-call should respond to common failures)
   - Known operational risks (single points of failure, noisy alerts, manual steps) and current mitigations

9. ## Current Gaps & Technical Roadmap
   - Known limitations and tech debt (with brief rationale)
   - Short-term technical improvements (next 1–3 months)
   - Medium-term improvements (3–12 months, if known)
   - Open technical questions for leadership/principal engineering input

### Style
- Use neutral, professional tone
- Be opinionated where relevant (call out tradeoffs explicitly)
- Avoid generic fluff; every bullet should convey real information
- Prefer referencing concrete codebase elements (components, services, modules, routes, configs) whenever possible

Now, using the required inputs (project name + features to cover), along with any optional codebase reference and project context, generate the full Markdown draft for all sections.
