# Retrofit Plan & Product Requirements Document (PRD)

## 1. Executive Summary
The objective of this project is to migrate the existing Workspace MCP server (from a local, Node.js-based `stdio` architecture) to a completely serverless, Edge-native architecture on Cloudflare Workers.

The current implementation relies heavily on Node.js native paradigms, local file systems for state management (`fs`), and synchronous operations that are incompatible with Cloudflare's V8 Edge environment. By transitioning to Cloudflare Workers, we aim to deliver a globally distributed, low-latency MCP server capable of stateless authentication, highly concurrent streaming interactions, and AI-augmented capabilities powered by Cloudflare's developer stack (Workers AI, Vectorize, D1, and KV).

This modernization will shift the primary transport layer from `stdio` to HTTP Server-Sent Events (SSE), unlocking multi-tenant architectures and improving reliability for AI assistants consuming the tools.

## 2. Current vs. Target Architecture

The migration fundamentally changes how the server interacts with both the user and the underlying system environment, replacing local Node.js paradigms with Cloudflare Edge-native solutions.

| Component | Current Architecture (Local Node.js) | Target Architecture (Cloudflare Workers Edge) |
| :--- | :--- | :--- |
| **Language & Framework** | Node.js, standard npm packages | TypeScript, Hono.js, Edge-compatible libraries |
| **Transport Layer** | `stdio` via `@modelcontextprotocol/sdk/server/stdio.js` | HTTP Server-Sent Events (SSE) via `@modelcontextprotocol/sdk/server/sse.js` with Hono POST endpoints |
| **Authentication Flow** | Local OAuth callback handling, potentially using `net` or Express | Stateless OAuth 2.0 flow via standard `fetch` and Hono redirect endpoints |
| **Token Storage** | Local file system using `fs` (e.g., `token.json` or credentials directory) | Cloudflare KV (Encrypted access/refresh tokens securely keyed by User/Session ID) |
| **Google APIs / Tools** | Wrapped Google Workspace APIs (Gmail, Drive, Calendar) using Node.js clients | Raw `fetch` API requests or Edge-compatible clients, authenticated via stateless Bearer tokens |
| **Dependencies** | Node.js native APIs (`fs`, `path`, `net`, `crypto`, `child_process`) | Strictly forbidden native APIs. Replaced with Web Crypto API and Cloudflare bindings (KV/D1). |
| **Execution Model** | Long-running Node.js process | Ephemeral V8 Isolates, asynchronous event-driven lifecycle using `ctx.waitUntil()` |

## 3. Feature Expansion Strategy

By leveraging Cloudflare's ecosystem, we will expand the MCP server's capabilities far beyond standard API wrappers:

*   **Workers AI + Vectorize Pipeline:**
    *   **Goal:** Provide semantic search tools over a user's Gmail and Google Drive.
    *   **Implementation:** When a user queries "Find documents about the Q3 budget," the server fetches relevant Drive files or Gmail threads (via Google API), chunks the text, and generates embeddings using Workers AI (`@cf/baai/bge-large-en-v1.5`). These embeddings are stored and indexed in Vectorize, allowing the LLM to execute fast, semantic proximity searches rather than relying solely on keyword matching.
*   **D1 (Relational Data & Logging):**
    *   **Goal:** Maintain an asynchronous audit trail and store complex relational data.
    *   **Implementation:** All tool executions (e.g., `create_draft_email`, `search_calendar`) are intercepted and logged to a Cloudflare D1 database. To prevent blocking the SSE response stream to the LLM, these inserts must be strictly wrapped in `ctx.waitUntil()`. D1 will also be used to store structured user prompt templates or application configuration data via a modular Drizzle ORM schema.
*   **KV (Key-Value State & Memory):**
    *   **Goal:** Enable agentic memory and fast caching.
    *   **Implementation:** KV acts as the primary store for encrypted OAuth tokens. Additionally, it serves as a "scratchpad" for the LLM to store intermediate reasoning steps or cache expensive Google Workspace API responses (e.g., the folder structure of Google Drive), drastically reducing latency on subsequent tool calls.

## 4. Migration Roadmap

*   **Phase 1: Foundation & Types:** Initialize the Cloudflare Worker with `wrangler`, configure `hono`, and set up the `@modelcontextprotocol/sdk/server/sse.js` transport layer. Define global environment bindings (`Env`) in `worker-configuration.d.ts` (managing configuration via `wrangler.jsonc`).
*   **Phase 2: Stateless Authentication:** Implement the Google OAuth flows statelessly. Configure Cloudflare KV bindings and build the token storage/refresh logic, ensuring encryption at rest using Web Crypto API instead of Node.js `crypto`.
*   **Phase 3: Core Tools Porting & Edge Refactoring:** Rewrite the core Workspace tools (Gmail `send_email`, Calendar `get_events`, Drive `list_files`) to rely on Edge-compatible stateless `fetch` logic. Completely strip out Node.js native dependencies (`fs`, `path`, `child_process`).
*   **Phase 4: Cloudflare Integrations:** Introduce D1 bindings with Drizzle ORM for asynchronous logging using `ctx.waitUntil()`. Implement the Workers AI and Vectorize pipeline for semantic search tools.
*   **Phase 5: Testing & Hardening:** Verify SSE streaming stability over Hono, test OAuth refresh cycles under KV's eventual consistency constraints, and ensure no script execution timeouts are hit during D1 inserts, large file processing, or embedding generation.
