# Workspace MCP Cloudflare Retrofit: Product Requirements Document (PRD)

## 1. Executive Summary
The primary objective of this project is to migrate the existing open-source Google Workspace MCP (Model Context Protocol) server—currently implemented as a stateful, local Node.js application—to a fully serverless, Edge-native architecture on Cloudflare Workers using TypeScript.

This retrofit will achieve infinite scalability and zero-maintenance infrastructure while deeply integrating the Cloudflare Developer Stack (Vectorize, Workers AI, D1, KV). Crucially, the system must act as a multi-tenant service, capable of seamlessly interacting with multiple distinct Google accounts (e.g., standard consumer `jmbish04@gmail.com` vs Workspace `justin@126colby.com`) simultaneously through a Hybrid Credential Resolver.

## 2. Current vs. Target Architecture

| Component | Current Architecture (Node.js/Local) | Target Architecture (Cloudflare Workers/Edge) |
| :--- | :--- | :--- |
| **Language & Runtime** | Node.js | TypeScript (Hono.js running on V8 Edge) |
| **Transport Protocol** | `stdio` primarily | Exclusively HTTP POST and Server-Sent Events (SSE) |
| **Authentication Flow** | Local OAuth flow | Hybrid Edge Auth (KV for OAuth, Secrets for Service Accounts) |
| **State & Token Storage** | Local File System (`token.json`, `credentials.json`) | Encrypted Key-Value pairs in Cloudflare KV & Worker Secrets |
| **Google API Client** | Node.js Native / Stateful | Native `fetch` API wrapping Google REST endpoints |
| **Logging & Telemetry** | Local file logging / Synchronous | Asynchronous SQLite inserts via Cloudflare D1 |

### Architectural Translation Notes:
1.  **Transport Shift (`stdio` -> SSE):** Cloudflare Workers do not support stdin/stdout streams for long-running RPC. The `@modelcontextprotocol/sdk/server/sse.js` must be implemented alongside Hono to provide the `/sse` connection endpoint and the `/message` ingress endpoint.
2.  **Stateless OAuth:** Since the Edge filesystem is read-only and ephemeral, the OAuth 2.0 flow must be entirely HTTP-driven. Tokens will be retrieved during the callback and stored in Cloudflare KV, keyed by a session or user ID.
3.  **Dependency Purge:** No Node.js polyfills (`fs`, `net`, `child_process`) should be relied upon. The application must exclusively use Web Standards (Fetch, Streams, Web Crypto).

## 3. Feature Expansion Strategy

### A. Authentication & Multi-Tenancy Strategy (Hybrid Credential Resolver)
To support simultaneous interactions across different account types, the Worker will implement a dynamic Auth Resolver Factory supporting three modes:

*   **Mode A: Standard OAuth 2.0 (User-Consented):** Used for standard consumer accounts. Client ID/Secret live in Cloudflare Secrets. The user's dynamic Access/Refresh Tokens are stored in Cloudflare KV (e.g., `oauth:jmbish04@gmail.com`). The Worker provides endpoints for the OAuth callback and handles automatic token rotation.
*   **Mode B: Service Account (Direct):** Used for backend integrations. The static Service Account JSON key is stored securely as a Cloudflare Secret environment variable, never in KV or plaintext.
*   **Mode C: Service Account with Domain-Wide Delegation (DWD):** Used for Workspace accounts. Stores credentials identical to Mode B, but instantiates the Google API client to impersonate a specific user (via the `subject` parameter in the JWT client).

**Multi-Account Tool Routing:**
Every relevant MCP tool (e.g., `semantic_workspace_search`, `read_email`) will include a required `target_email` parameter. The Auth Resolver will intercept this parameter, determine the correct Auth Mode, retrieve credentials (KV or Secrets), and instantiate the appropriate Google Auth Client in memory to execute the request natively on the Edge (potentially utilizing `nodejs_compat` or lightweight Web Crypto alternatives like `jose` if `google-auth-library`'s `crypto` usage fails).

### B. Semantic Workspace Search (Workers AI + Vectorize)
*   **Objective:** Move beyond Google's native keyword search by enabling LLMs to query documents and emails semantically.
*   **Pipeline:** Ingestion -> Chunking -> Embedding via `env.AI.run('@cf/baai/bge-large-en-v1.5')` -> Indexing vectors and metadata in Cloudflare Vectorize.
*   **MCP Integration:** A new tool, `semantic_workspace_search`, accepting natural language queries and returning highly relevant contextual snippets.

### C. Relational Data & Observability (Cloudflare D1)
*   **Interaction Logging:** Every execution of an MCP tool is intercepted and logged asynchronously to a D1 `interactions_log` table using `ctx.waitUntil()` to avoid blocking LLM responses.
*   **Prompt Management:** A `saved_prompts` table stores reusable workflows.
*   **MCP Integration:** Tools: `save_prompt`, `get_prompt`, and `query_interaction_logs`.

### D. Agentic Memory & Caching (Cloudflare KV)
*   **Caching:** Read-heavy API responses (Drive trees, Calendar lists) are cached in KV with TTLs.
*   **Scratchpad Memory:** Provides the LLM with short-term, cross-session memory.
*   **MCP Integration:** Tools: `set_memory`, `get_memory`, and `delete_memory`.

## 4. Migration Roadmap

*   **Phase 1: Infrastructure & Scaffolding (Days 1-2)**
    *   Initialize Cloudflare Worker (`wrangler.jsonc`, `tsconfig.json`).
    *   Provision D1, KV, Vectorize, AI bindings, and Secrets for Service Accounts.
    *   Implement Drizzle ORM schemas and run initial D1 migrations.
*   **Phase 2: Hybrid Edge Authentication (Days 3-5)**
    *   Setup Hono router for `/sse`, `/message`, and `/auth/callback` endpoints.
    *   Implement Hybrid Credential Resolver (Mode A, B, C) and test Edge crypto compatibility.
*   **Phase 3: Core Workspace Tools API Port & Tool Routing (Days 6-10)**
    *   Rewrite tool wrappers to enforce the `target_email` parameter and instantiate the correct auth client dynamically.
    *   Implement KV caching layers and async D1 interaction logging middleware.
*   **Phase 4: AI & Semantic Expansion (Days 11-14)**
    *   Build the ingestion, chunking, and embedding pipeline.
    *   Integrate Vectorize and expose the `semantic_workspace_search` tool.

---

```json
{
  "queries": [
    {
      "topic": "SSE Connections and Timeouts on Workers",
      "question": "How do Cloudflare Workers handle long-running Server-Sent Events (SSE) connections specifically using Hono? Are there maximum execution time limits (e.g., 30s) or idle timeouts that will sever the connection between the MCP client and the Edge server?",
      "reason": "MCP clients expect a persistent SSE connection. We must understand Worker limits to ensure the connection does not drop during idle periods or long tool executions."
    },
    {
      "topic": "D1 Async Execution via waitUntil",
      "question": "When using `ctx.waitUntil()` to execute a Cloudflare D1 insert asynchronously, is there a risk of the operation failing silently if the Worker process is terminated immediately after responding to the client? What are the best practices for robust async logging in D1?",
      "reason": "We must guarantee that our interaction logs are written without adding latency to the LLM response, but we need to know if `waitUntil` provides strong guarantees for database writes."
    },
    {
      "topic": "Workers AI Text Embedding Limits",
      "question": "What are the rate limits, concurrency limits, and maximum input token sizes for the `@cf/baai/bge-large-en-v1.5` model on Cloudflare Workers AI?",
      "reason": "To build a reliable semantic search pipeline, we need to know exactly how to chunk the Workspace documents and handle backpressure when embedding large emails or Drive files."
    },
    {
      "topic": "Model Context Protocol SDK Edge Compatibility",
      "question": "Are there any known issues or required polyfills for running the `@modelcontextprotocol/sdk/server/sse.js` in a Cloudflare V8 Edge environment? Does it implicitly rely on Node.js `EventEmitter` or specific streaming APIs that behave differently on Workers?",
      "reason": "The core of the server relies on this SDK. If it requires Node.js standard libraries, we may need to use `nodejs_compat` flags or find workarounds for the SSE transport."
    },
    {
      "topic": "KV Eventual Consistency Impacts on OAuth",
      "question": "How does Cloudflare KV's eventual consistency affect short-lived data like OAuth state tokens or recently refreshed access tokens? If we write an OAuth token during the callback and immediately try to read it on the next request, is there a risk of a stale read?",
      "reason": "OAuth flows rely on immediate consistency between writing a token and reading it for the next API call. We need to know if KV's eventual consistency will break the auth loop."
    },
    {
      "topic": "Google Auth Library Edge Crypto Compatibility",
      "question": "Are there any known polyfill requirements, `nodejs_compat` flag necessities, or `crypto` module limitations when running the official `google-auth-library` (specifically `OAuth2Client` and `JWT`) on Cloudflare Workers?",
      "reason": "We must generate and sign Service Account JWTs natively on the Edge. The Node.js crypto module often fails in V8 Edge, so we need to know if the official library is compatible or if we must use Web Crypto/jose alternatives."
    },
    {
      "topic": "Service Account JSON in Worker Secrets",
      "question": "What are the best practices and size limits for storing and parsing large multi-line Service Account JSON strings (with `\\n` characters) within Cloudflare Worker Secrets?",
      "reason": "Service Account keys are complex JSON objects with embedded private keys containing newlines. We need to ensure Worker Secrets can safely store and inject them without formatting corruption."
    }
  ]
}
```
