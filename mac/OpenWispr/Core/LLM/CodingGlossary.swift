import Foundation

/// Generic developer vocabulary the guard accepts with a lower phonetic bar. Personal names belong in the local dictionary.
enum CodingGlossary {
    static let terms = [
        "git", "commit", "push", "pull", "merge", "rebase", "branch", "main", "repo", "diff", "stash", "checkout", "worktree", "pull request",
        "API", "REST", "JSON", "YAML", "TOML", "SQL", "SQLite", "Postgres", "Redis", "HTTP", "URL", "CLI", "SDK", "UI", "UX", "CSS", "HTML",
        "JavaScript", "TypeScript", "Python", "Rust", "Go", "C#", ".NET", "Node", "npm", "pnpm", "yarn", "React", "Next.js", "Vite", "Astro", "Tailwind", "FastAPI",
        "Docker", "Kubernetes", "AWS", "Vercel", "GitHub", "GitLab", "Claude", "Claude Code", "Opus", "Sonnet", "Haiku", "Fable", "Cursor", "Codex", "ChatGPT", "OpenAI", "Anthropic",
        "MCP", "LLM", "Token", "Prompt", "Agent", "Agenten", "Subagent", "Hook", "Skill", "Frontend", "Backend", "Deploy", "Build", "Bug", "Fix", "Refactor", "Test", "Sweep",
        "Log", "Logs", "Debug", "Endpoint", "Webhook", "Server", "Client", "Browser", "Terminal", "Shell", "PowerShell", "Bash", "Function", "Variable", "Array", "async", "await",
        "Cache", "Queue", "Worker", "Thread", "Timeout", "Retry", "Lint", "Linter", "Typecheck", "Playwright", "Vitest", "Jest", "pytest", "venv", "localhost", "Tailscale",
        "Wispr Flow", "Parakeet", "Whisper",
    ]

    /// Lowercased, because the guard compares case-insensitively.
    static func with(_ dictionary: [DictionaryHint]) -> Set<String> {
        Set((terms + dictionary.map(\.term)).map { $0.lowercased() })
    }
}
