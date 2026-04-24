# Dev Conventions

Language-agnostic development conventions for LLM agents.

## Overview

Copy `conventions/` to any project. Point LLM agents at `AGENTS.md` or `DEVELOPMENT.md` to apply conventions.

## Files

| File | Purpose |
|------|---------|
| [`AGENTS.md`](conventions/AGENTS.md) | Quick reference for LLM assistants |
| [`DEVELOPMENT.md`](conventions/DEVELOPMENT.md) | Comprehensive development rules (1.5~3k lines) |
| [`DEV-EXAMPLES.md`](conventions/DEV-EXAMPLES.md) | Concrete examples demonstrating conventions |
| [`SKILL.md`](SKILL.md) | Non-obvious conventions only |
| [`dev-conventions.sh`](conventions/dev-conventions.sh) | Unified CLI (changelog, sync, lint) |
| [`context.md`](conventions/context.md) | File index for conventions/ directory |
| [`src/lib.sh`](conventions/src/lib.sh) | Shared utilities |
| [`src/changelog.sh`](conventions/src/changelog.sh) | Changelog generation and merge workflow |
| [`src/sync.sh`](conventions/src/sync.sh) | Remote convention file syncing |
| [`src/lint.sh`](conventions/src/lint.sh) | Shell script linting and formatting |
| [`src/context.md`](conventions/src/context.md) | File index for src/ directory |

## Setup

1. Copy the `conventions/` directory to your project root
2. Make the CLI executable: `chmod +x conventions/dev-conventions.sh`
3. Point agents at `AGENTS.md` or `DEVELOPMENT.md`

## Usage

```bash
# Interactive TUI (requires gum)
./conventions/dev-conventions.sh

# Sync conventions from remote
./conventions/dev-conventions.sh sync
./conventions/dev-conventions.sh sync --branch dev
./conventions/dev-conventions.sh sync --version v1.2.0
./conventions/dev-conventions.sh sync --dry-run

# Generate changelog and merge
./conventions/dev-conventions.sh changelog
./conventions/dev-conventions.sh changelog --target dev
./conventions/dev-conventions.sh changelog --target dev --yes
./conventions/dev-conventions.sh changelog --target dev --theirs
./conventions/dev-conventions.sh changelog --generate-only
./conventions/dev-conventions.sh changelog --rename

# Lint shell scripts
./conventions/dev-conventions.sh lint
./conventions/dev-conventions.sh lint --format
./conventions/dev-conventions.sh lint --install-hook

# Help
./conventions/dev-conventions.sh help
./conventions/dev-conventions.sh changelog --help
```

## Conventions Covered

- File headers and code style (Nix, Fish, Python, Bash, Rust, Go, TypeScript)
- Naming conventions and project structure
- Comments, navigation, and file hygiene
- DRY refactoring patterns
- Commit message format and workflow
- Documentation guidelines
- Validation and CI/CD configuration
- Core principles (KISS, DRY, maintainable over clever)

See [`DEVELOPMENT.md`](conventions/DEVELOPMENT.md) for full details.
