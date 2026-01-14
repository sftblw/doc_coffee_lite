# DocCoffeeLite ☕

DocCoffeeLite is a professional EPUB translation tool designed for high-quality, structurally-sound book translations using Large Language Models (LLMs). It features a highly resilient, batch-oriented translation engine capable of handling massive documents with narrative continuity.

## 🚀 Key Features

### 🧠 Intelligent Translation Engine
- **Atomic Batch Translation**: Automatically groups translation units based on character limits and unit counts to maximize LLM throughput while maintaining context.
- **Rolling Context Summary**: Passes a continuous narrative "baton" between batches. The LLM summarizes each batch to guide the next, ensuring consistency in characters, tone, and plot.
- **Semantic Placeholder System**: Uses specialized tags like `[[p_1]]` or `[[h1_2]]` to protect EPUB/HTML structure while giving the LLM explicit context about the element's role.

### 🛡️ Robustness & Reliability
- **Structured Output Enforcement**: Utilizes native JSON Schema (Structured Outputs) to guarantee valid data formats from the LLM.
- **Self-Healing Feedback Loop**: Automatically detects malformed responses or missing tags and provides specific feedback to the LLM for instant correction.
- **Crash Resilience**: Background workers are designed to recover automatically from server restarts or crashes, resuming exactly where they left off.

### ⚡ Performance & Scalability
- **Smart Load Balancing**: Managed LLM pool (`LlmPool`) that intelligently distributes requests across multiple GPU nodes (e.g., Mac Studio, DGX Spark) with health tracking.
- **Concurrent Processing**: Leverages Oban for reliable, parallel background job execution.
- **Real-time UI**: Phoenix LiveView-powered dashboard with live progress counts, recent activity logs, and dynamic ETA calculation.

## 🛠️ Setup

### Prerequisites
- Elixir 1.15+ & Erlang/OTP 26+
- PostgreSQL
- LLM Provider (Ollama or OpenAI-compatible API)

### Configuration
Create a `.env` file in the project root:
```bash
# LLM Server(s) - Comma-separated for load balancing
LIVE_LLM_SERVER="http://192.168.1.10:11434,http://192.168.1.11:11434"
LIVE_LLM_MODEL="gpt-oss:20b"

# Worker Concurrency
OBAN_CONCURRENCY=3
```

### Installation
1. Install dependencies: `mix deps.get`
2. Setup database: `mix ecto.setup`
3. Start server: `mix phx.server`

Visit `http://localhost:4000` to start your first project.

## 📖 Usage Flow
1. **Create Project**: Upload your `.epub` file and select target language.
2. **Prepare**: The system granularly decomposes the book into translation units and generates translation policies.
3. **Configure LLM**: Set up your model endpoints (via `.env` or UI).
4. **Translate**: Click "Start". Monitor real-time progress and live translation snippets.
5. **Export**: Once 100% complete, download your translated EPUB with original formatting perfectly preserved.

---
Built with Elixir, Phoenix, and ❤️ by sftblw.
