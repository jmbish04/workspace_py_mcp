-- Create interactions_log table
CREATE TABLE IF NOT EXISTS interactions_log (
    id TEXT PRIMARY KEY,
    tool_name TEXT NOT NULL,
    parameters TEXT,
    response TEXT,
    latency_ms INTEGER,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Create saved_prompts table
CREATE TABLE IF NOT EXISTS saved_prompts (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    prompt_text TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
