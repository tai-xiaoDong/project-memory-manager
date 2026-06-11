# Project Memory Manager

[English](#english) · [中文](#中文)

---

<a id="english"></a>

## 🧠 What Is This?

**Project Memory Manager** is an [Agent Skill](https://agentskills.io/) for AI coding assistants (Claude Code, Cursor, Cline, etc.). It provides a self-maintaining project memory system that solves three critical problems:

- **AI Hallucination** — The AI lacks project context and fabricates modules, dependencies, or APIs that don't exist
- **Log Bloat** — Activity logs grow indefinitely, flooding the context window and burying critical information
- **Lost Decisions** — Historical decisions and lessons learned can't be effectively retrieved or reused

### How It Works

```
┌─────────────────────────────────────────────────────┐
│                  dev-log-summary.md                  │
│         (Permanent constraints & decisions)          │
├─────────────────────────────────────────────────────┤
│                 dev-log/ (daily files)                │
│        (Rolling window — max 15 daily files)          │
│                                                      │
│   New entry arrives ──► oldest 5 auto-archived ──►   │
├─────────────────────────────────────────────────────┤
│                 dev-log-archive/                      │
│       (Historical — split by quarter, e.g. 2026-Q2)  │
└─────────────────────────────────────────────────────┘
```

Every time the AI completes a code change, it:
1. Appends a structured entry to `docs/dev-log/YYYY-MM-DD.md`
2. Syncs critical changes to `docs/dev-log-summary.md`
3. Auto-archives overflow daily files (with experience extraction)

## ✨ Key Features

| Feature | Description |
|---------|-------------|
| **Rolling Window** | Keeps only the latest 15 daily log files — old ones auto-archive by quarter |
| **Experience Extraction** | Recurring pitfalls (`⚠️` or `#promote`) get promoted to Summary (with user confirmation) |
| **Circuit Breaker** | Warns and suggests archival if a daily file exceeds 200 lines or total exceeds 30 files (never interrupts ongoing code generation) |
| **Session Cache** | Reads memory files once per session, re-reads only on explicit trigger |
| **Monorepo Support** | Global summary + per-package logs, global Summary is the hard constraint on conflict |
| **Audit Trail** | Optional change history tracking (default OFF, enable on demand) |
| **Validation Script** | Bash-based consistency checker — no Python required |

## 📁 Directory Structure

```
project-memory-manager/
├── SKILL.md                     # Skill definition (L1 metadata + L2 instructions)
├── LICENSE.txt                  # MIT License
├── README.md                    # This file
├── scripts/
│   └── validate.sh              # Log consistency validator
└── templates/
    ├── summary-template.md      # Template for dev-log-summary.md
    └── log-template.md          # Template for daily log files
```

## 🚀 Installation

### Claude Code (CLI)

```bash
# Copy to your project's skill directory
cp -r project-memory-manager/ .claude/skills/project-memory-manager/
```

### VS Code Extension (Claude / Cursor)

```bash
# Option A: Claude Code skill directory
cp -r project-memory-manager/ .claude/skills/project-memory-manager/

# Option B: Project instructions file
cat project-memory-manager/SKILL.md >> CLAUDE.md
```

### Other AI Tools

| Tool | Location |
|------|----------|
| Cursor | `.cursorrules` in project root |
| Continue | `.continue.rules` in project root |
| GitHub Copilot | `AGENTS.md` in project root |

## 📖 Usage

### First Time

Say to your AI assistant:

> "Initialize project memory files. My tech stack is [your tech stack]."

The AI will create `docs/dev-log/`, `docs/dev-log-summary.md`, and `docs/dev-log-archive/` using the templates.

### Daily Workflow

No extra commands needed. The AI automatically:

1. **Reads** memory files before any coding task
2. **Writes** a log entry after each logical task completes (appends to today's daily file, not after every file edit)
3. **Archives** old daily files when the log directory exceeds 15 files
4. **Promotes** recurring pitfalls to Summary (asks for confirmation)

### Manual Commands

| Command | Action |
|---------|--------|
| `"Re-read dev-log"` | Force re-read memory files |
| `"Remember this decision"` | AI asks whether to store as ADR or dev-log entry |
| `"Enable audit trail"` | Turn on change history in Summary |
| `"Archive old entries now"` | Manually trigger archival |
| `"Uninstall project memory"` | Remove injected rules and validation script (keeps log data) |

### Validation

Run the consistency checker anytime:

```bash
bash scripts/validate.sh docs/dev-log/

# With summary validation:
bash scripts/validate.sh docs/dev-log/ --summary docs/dev-log-summary.md

# Strict mode (warnings = errors):
bash scripts/validate.sh docs/dev-log/ --strict
```

## 📋 Log Entry Format

Each entry in `docs/dev-log/YYYY-MM-DD.md` follows this structure (≤ 500 chars):

```markdown
### [14:30] Add Redis caching to user API @alice
- **Change**: Replaced in-memory cache with Redis for /api/users endpoint
- **Deps**: added redis@5.0.0, removed node-cache
- **Gotcha**: Redis URL must use rediss:// (TLS) in production — connection hangs silently with redis://
- **TODO**: Add Redis health check endpoint
```

## 🏗️ Monorepo Setup

```
docs/
  dev-log-summary.md       # Global constraints (e.g., "All packages use pnpm")
packages/
  auth/
    docs/
      dev-log/             # Auth-specific daily logs
      dev-log-archive/
  api/
    docs/
      dev-log/             # API-specific daily logs
```

- AI reads **both** global Summary + current package's daily logs
- **Global Summary takes priority** on conflict (hard constraints override sub-package preferences)
- Only updates the current package's daily logs unless change is cross-cutting

## 🔧 Troubleshooting

| Problem | Solution |
|---------|----------|
| AI doesn't read logs automatically | Start your message with "Follow project-memory-manager skill" |
| Archive files grow too large | Split by year: `archive/2025/`, `archive/2026/` — AI auto-adapts |
| Branch conflicts in dev-log | Only maintain dev-log on main branch; resolve conflicts on merge |

## 📜 License

MIT — see [LICENSE.txt](LICENSE.txt).

---

<a id="中文"></a>

## 🧠 这是什么？

**Project Memory Manager** 是一个面向 AI 编程助手（Claude Code、Cursor、Cline 等）的 [Agent Skill](https://agentskills.io/)。它提供了一套自维护的项目记忆系统，解决三个核心问题：

- **AI 幻觉** — AI 缺乏项目上下文，虚构不存在的模块、依赖或 API
- **日志膨胀** — 活动日志无限增长，淹没关键信息并撑爆上下文窗口
- **决策丢失** — 历史决策和经验教训无法被有效检索和复用

### 工作原理

```
┌─────────────────────────────────────────────────────┐
│                  dev-log-summary.md                  │
│             （永久约束、重大问题、待办）                │
├─────────────────────────────────────────────────────┤
│               dev-log/（按日期拆分）                   │
│         （滚动窗口 — 最多保留 15 个日志文件）            │
│                                                      │
│   新条目写入 ──► 最旧 5 个文件自动归档 ──►             │
├─────────────────────────────────────────────────────┤
│                 dev-log-archive/                      │
│        （历史归档 — 按季度拆分，如 2026-Q2）            │
└─────────────────────────────────────────────────────┘
```

每当 AI 完成一次代码变更时，它会：
1. 向 `docs/dev-log/YYYY-MM-DD.md` 追加一条结构化记录
2. 将关键变更同步到 `docs/dev-log-summary.md`
3. 自动归档溢出的日志文件（并提取经验）

## ✨ 核心特性

| 特性 | 说明 |
|------|------|
| **滚动窗口** | 仅保留最近 15 个日志文件 — 旧文件按季度自动归档 |
| **经验提取** | 反复出现的坑（标记 `⚠️` 或 `#promote`）会被提升到摘要层（需用户确认） |
| **熔断机制** | 单文件超过 200 行或总数超过 30 个文件时警告并建议归档（不会中断正在进行的代码生成） |
| **会话缓存** | 每次会话仅读取一次记忆文件，仅在明确触发时重新读取 |
| **Monorepo 支持** | 全局摘要 + 各包独立日志，冲突时全局摘要为硬约束优先 |
| **审计追踪** | 可选的变更历史记录（默认关闭，按需开启） |
| **校验脚本** | 基于 Bash 的一致性校验器 — 无需 Python 环境 |

## 📁 目录结构

```
project-memory-manager/
├── SKILL.md                     # Skill 定义（L1 元数据 + L2 指令）
├── LICENSE.txt                  # MIT 许可证
├── README.md                    # 本文件
├── scripts/
│   └── validate.sh              # 日志一致性校验脚本
└── templates/
    ├── summary-template.md      # dev-log-summary.md 模板
    └── log-template.md          # 每日日志文件模板
```

## 🚀 安装

### Claude Code（CLI）

```bash
# 复制到项目的 skill 目录
cp -r project-memory-manager/ .claude/skills/project-memory-manager/
```

### VS Code 扩展（Claude / Cursor）

```bash
# 方式 A：Claude Code skill 目录
cp -r project-memory-manager/ .claude/skills/project-memory-manager/

# 方式 B：项目指令文件
cat project-memory-manager/SKILL.md >> CLAUDE.md
```

### 其他 AI 工具

| 工具 | 放置位置 |
|------|---------|
| Cursor | 项目根目录的 `.cursorrules` |
| Continue | 项目根目录的 `.continue.rules` |
| GitHub Copilot | 项目根目录的 `AGENTS.md` |

## 📖 使用方法

### 首次使用

对 AI 助手说：

> "请根据 project-memory-manager skill 初始化项目记忆文件，我的技术栈是 [你的技术栈]"

AI 会使用模板创建 `docs/dev-log/`、`docs/dev-log-summary.md` 和 `docs/dev-log-archive/`。

### 日常使用

无需额外指令。AI 会自动：

1. **读取** — 编码任务前自动加载记忆文件
2. **写入** — 每次逻辑任务完成后追加日志条目到当天的日志文件（非每次文件编辑）
3. **归档** — 日志文件超过 15 个时自动归档旧文件
4. **提取** — 反复出现的坑会被提示提升到摘要层（需确认）

### 手动指令

| 指令 | 动作 |
|------|------|
| `"重新读取 dev-log"` | 强制重新读取记忆文件 |
| `"记住这个决策"` | AI 会询问是写入 ADR 还是 dev-log |
| `"启用审计追踪"` | 在摘要中开启变更历史记录 |
| `"现在归档旧条目"` | 手动触发归档 |
| `"卸载 project memory"` | 移除注入的规则和校验脚本（保留日志数据） |

### 校验

随时运行一致性校验：

```bash
bash scripts/validate.sh docs/dev-log/

# 同时校验摘要文件：
bash scripts/validate.sh docs/dev-log/ --summary docs/dev-log-summary.md

# 严格模式（警告也视为错误）：
bash scripts/validate.sh docs/dev-log/ --strict
```

## 📋 日志条目格式

`docs/dev-log/YYYY-MM-DD.md` 中的每条记录遵循以下格式（≤ 500 字符）：

```markdown
### [14:30] 为用户 API 添加 Redis 缓存 @alice
- **Change**: 将 /api/users 端点的内存缓存替换为 Redis
- **Deps**: 新增 redis@5.0.0，移除 node-cache
- **Gotcha**: 生产环境必须使用 rediss://（TLS）— 用 redis:// 会静默挂起
- **TODO**: 添加 Redis 健康检查端点
```

## 🏗️ Monorepo 配置

```
docs/
  dev-log-summary.md       # 全局约束（如"所有包使用 pnpm"）
packages/
  auth/
    docs/
      dev-log/             # auth 包的每日日志
      dev-log-archive/
  api/
    docs/
      dev-log/             # api 包的每日日志
```

- AI 同时读取**全局摘要**和**当前子包的每日日志**
- **冲突时全局摘要为硬约束优先**，子包仅在实现细节层面有优先权
- 只更新当前子包的每日日志，除非变更影响整个仓库

## 🔧 故障排查

| 问题 | 解决方案 |
|------|---------|
| AI 不主动读取日志 | 在对话开头说"请遵循 project-memory-manager skill" |
| 归档文件过大 | 按年份拆分：`archive/2025/`、`archive/2026/` — AI 会自动适应 |
| 多分支协作冲突 | 建议只在主分支维护 dev-log，合并时人工解决冲突 |

## 📜 许可证

MIT — 详见 [LICENSE.txt](LICENSE.txt)。
