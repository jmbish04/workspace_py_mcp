# Workspace MCP Cloudflare Retrofit: Product Requirements Document (PRD)

## 1. Executive Summary
The primary objective of this project is to migrate the existing open-source Google Workspace MCP (Model Context Protocol) server—currently implemented as a stateful, local Node.js application—to a fully serverless, Edge-native architecture on Cloudflare Workers using TypeScript.

This retrofit will not only achieve infinite scalability and zero-maintenance infrastructure but also supercharge the server by deeply integrating the Cloudflare Developer Stack. By utilizing Cloudflare Vectorize and Workers AI, we will introduce semantic search capabilities across Google Workspace. Additionally, Cloudflare D1 will provide structured observability and prompt management, while Cloudflare KV will deliver high-performance caching and agentic memory for LLMs.

## 2. Current vs. Target Architecture

| Component | Current Architecture (Node.js/Local) | Target Architecture (Cloudflare Workers/Edge) |
| :--- | :--- | :--- |
| **Language & Runtime** | Node.js | TypeScript (Hono.js running on V8 Edge) |
| **Transport Protocol** | `stdio` primarily | Exclusively HTTP POST and Server-Sent Events (SSE) |
| **Authentication Flow** | Local OAuth flow | Stateless HTTP callbacks (`/auth/callback`) |
| **State & Token Storage** | Local File System (`token.json`, `credentials.json`) | Encrypted Key-Value pairs in Cloudflare KV |
| **Google API Client** | Node.js Native / Stateful | Native `fetch` API wrapping Google REST endpoints |
| **Logging & Telemetry** | Local file logging / Synchronous | Asynchronous SQLite inserts via Cloudflare D1 |

### Architectural Translation Notes:
1.  **Transport Shift (`stdio` -> SSE):** Cloudflare Workers do not support stdin/stdout streams for long-running RPC. The `@modelcontextprotocol/sdk/server/sse.js` must be implemented alongside Hono to provide the `/sse` connection endpoint and the `/message` ingress endpoint.
2.  **Stateless OAuth:** Since the Edge filesystem is read-only and ephemeral, the OAuth 2.0 flow must be entirely HTTP-driven. Tokens will be retrieved during the callback and stored in Cloudflare KV, keyed by a session or user ID.
3.  **Dependency Purge:** No Node.js polyfills (`fs`, `net`, `child_process`) should be relied upon. The application must exclusively use Web Standards (Fetch, Streams, Web Crypto).

## 3. Feature Expansion Strategy

### A. Semantic Workspace Search (Workers AI + Vectorize)
*   **Objective:** Move beyond Google's native keyword search by enabling LLMs to query documents and emails semantically.
*   **Pipeline:**
    1.  **Ingestion:** A background task (or triggered MCP tool) fetches recent Gmail threads or Google Docs.
    2.  **Chunking:** Text is split into manageable chunks (e.g., 500-1000 tokens).
    3.  **Embedding:** Calls `env.AI.run('@cf/baai/bge-large-en-v1.5')` to generate vector embeddings for each chunk.
    4.  **Indexing:** The vectors, along with rich metadata (document ID, URL, snippet, timestamp), are upserted into a Cloudflare Vectorize index.
*   **MCP Integration:** A new tool, `semantic_workspace_search`, will accept natural language queries, embed them via Workers AI, query the Vectorize index, and return highly relevant, contextual snippets to the LLM.

### B. Relational Data & Observability (Cloudflare D1)
*   **Objective:** Implement an auditable system of record for LLM actions and a storage mechanism for complex prompts.
*   **Interaction Logging:** Every execution of an MCP tool will be intercepted by a middleware or wrapper. The request payload, response, and latency will be logged to a D1 `interactions_log` table.
    *   *Critical Constraint:* To ensure the fastest possible response to the LLM client, D1 inserts must be executed asynchronously using `ctx.waitUntil()`.
*   **Prompt Management:** A `saved_prompts` table will store reusable workflows or system instructions.
*   **MCP Integration:** New tools: `save_prompt`, `get_prompt`, and `query_interaction_logs` (allowing the LLM to inspect its own historical actions).

### C. Agentic Memory & Caching (Cloudflare KV)
*   **Objective:** Optimize Google API quota usage and provide the LLM with short-term, cross-session memory.
*   **Caching:** Read-heavy, slow-changing Google API responses (e.g., `list_drive_files` for root folders, calendar event lists for the current day) will be cached in KV with sensible TTLs (Time-To-Live).
*   **Scratchpad Memory:**
*   **MCP Integration:** New tools: `set_memory`, `get_memory`, and `delete_memory`. The LLM can use this to store JSON structures, pagination tokens, or reasoning steps that need to persist across stateless HTTP requests.

## 4. Migration Roadmap

*   **Phase 1: Infrastructure & Scaffolding (Days 1-2)**
    *   Initialize Cloudflare Worker (`wrangler.jsonc`, `tsconfig.json`).
    *   Provision D1, KV, Vectorize, and Workers AI bindings.
    *   Implement Drizzle ORM schemas and run initial D1 migrations.
*   **Phase 2: Core Server & Authentication (Days 3-5)**
    *   Setup Hono router for `/sse` and `/message` endpoints.
    *   Implement `@modelcontextprotocol/sdk` SSE transport.
    *   Build the stateless Google OAuth 2.0 flow using KV for token storage.
*   **Phase 3: Core Workspace Tools API Port (Days 6-10)**
    *   Rewrite the tool wrappers (Gmail, Drive, Calendar) into TypeScript `fetch` calls against Google REST APIs.
    *   Implement KV caching layers on top of these tools.
    *   Implement the asynchronous D1 interaction logging middleware.
*   **Phase 4: AI & Semantic Expansion (Days 11-14)**
    *   Build the ingestion, chunking, and embedding pipeline.
    *   Integrate Vectorize and expose the `semantic_workspace_search` tool.
    *   Implement Agentic Memory tools (`set_memory`, `get_memory`).

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
    }
  ]
}
```
