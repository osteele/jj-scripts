# Jujutsu Scripts

A collection of utility scripts for Jujutsu (jj) version control, including AI-powered commit message generation and workflow enhancements.

For Git version control scripts, see: https://github.com/osteele/git-scripts

For more development tools, see: https://osteele.com/software/development-tools

## Installation

Clone this repository and add it to your PATH, or copy the scripts to a directory already in your PATH.

To use the AI tools as jj subcommands (like `jj ai-describe`), add these aliases to your config:
```bash
jj config set --user 'aliases.ai-describe' '["util", "exec", "--", "jj-ai-describe"]'
jj config set --user 'aliases.ai-commit' '["util", "exec", "--", "jj-ai-commit"]'
```

## Jujutsu Tools

### `jj-squash-safe`
A smart squashing tool that finds the earliest ancestor where a commit can be safely squashed without creating merge conflicts. Unlike `jj squash`, this automatically determines the optimal target commit.

```bash
# Safe-squash current working copy into earliest conflict-free ancestor
jj-squash-safe

# Safe-squash a specific revision
jj-squash-safe abc123

# Preview what would happen without making changes
jj-squash-safe --dry-run

# Show detailed progress information
jj-squash-safe --verbose

# Combine options
jj-squash-safe --dry-run --verbose @
```

The script walks up the ancestor chain from the specified commit, testing each ancestor to determine if squashing would be safe. It stops when it encounters:
- Merge commits (multiple parents)
- The root of the repository
- Any ancestor where conflicts would occur

### `jj-export-bookmarks-as-tags`
Export Jujutsu bookmarks as git tags in the local repository. This command is analogous to `jj git export` but specifically for converting bookmarks to tags. Existing tags with the same name will be overwritten.

```bash
# Export a single bookmark as a tag
jj-export-bookmarks-as-tags release

# Export multiple bookmarks in one call
jj-export-bookmarks-as-tags release staging demo

# Preview what tags would be created/updated without executing
jj-export-bookmarks-as-tags --dry-run release
```

### `jj-push-bookmarks-as-tags`
Export Jujutsu bookmarks as git tags and push them to the `origin` remote. This command is analogous to `jj git push` - it first runs `jj-export-bookmarks-as-tags` to create/update local tags, then pushes them to the remote.

```bash
# Export and push a single bookmark as a tag
jj-push-bookmarks-as-tags release

# Export and push multiple bookmarks in one call
jj-push-bookmarks-as-tags release staging demo

# Force push tags (overwrite existing remote tags)
jj-push-bookmarks-as-tags --force release

# Preview what would be done without executing
jj-push-bookmarks-as-tags --dry-run release
```

### `jj-wrapper`
A wrapper for the `jj` command that provides subcommand expansion and custom alias support. This wrapper enables shortcuts and handles compound aliases like `git-force-push`.

Features:
- Expands shortcuts: `g`→`git`, `b`→`bookmark`, `ci`→`commit`, `desc`→`describe`, `st`→`status`
- Checks for compound aliases (e.g., `jj git force-push` looks for `git-force-push` alias)
- Falls through to the real `jj` command if no alias is found

To use, add this function to your shell configuration:
```bash
jj() {
    if command -v jj-wrapper > /dev/null; then
        jj-wrapper "$@"
    else
        command jj "$@"
    fi
}
```

```bash
# Use shortcuts
jj g push              # Expands to: jj git push
jj b list              # Expands to: jj bookmark list
jj st                  # Expands to: jj status

# Use compound aliases (if configured)
jj git force-push      # Uses git-force-push alias if it exists
```

## AI-Assisted Jujutsu Tools

These AI-powered tools use the `llm` command-line tool to generate conventional commit messages. You can configure a custom model for all commit message generation by setting an alias:

```bash
# Set a preferred model for commit messages
llm aliases set ai-commit-message "openrouter/google/gemini-2.5-flash-lite"
# Or use any other available model
llm aliases set ai-commit-message "claude-3.5-sonnet"
llm aliases set ai-commit-message "gpt-4"

# Check your current aliases
llm aliases

# Remove the alias to use the default model selection
llm aliases remove ai-commit-message
```

### `jj-ai-describe`
Generates conventional commit messages for Jujutsu revisions using AI. Analyzes the changes in a revision and creates a descriptive commit message following conventional commit format.

```bash
# Generate and apply message for current working copy
jj-ai-describe
# Or with the alias: jj ai-describe

# Generate message for a specific revision
jj-ai-describe <revision>

# Preview the message without applying it
jj-ai-describe -n

# Use a specific LLM model
jj-ai-describe --model gpt-4

# Provide additional instructions for the message
jj-ai-describe --prompt "Focus on the performance improvements"
```

### `jj-ai-commit`
Creates a new change with an AI-generated commit message, similar to `jj commit`. The AI analyzes the specified changes (or all changes) and creates a conventional commit message. Unlike `jj-ai-describe`, this command accepts filesets to selectively commit specific files.

```bash
# Commit all changes with AI-generated message
jj-ai-commit
# Or with the alias: jj ai-commit

# Commit specific files or directories
jj-ai-commit src/           # Commit changes in src/
jj-ai-commit README.md lib/  # Commit specific files

# Preview the message without creating the commit
jj-ai-commit -n

# Interactive selection of changes
jj-ai-commit -i

# Use a specific LLM model
jj-ai-commit --model openrouter/google/gemini-2.5-flash-lite

# Provide additional instructions for the message
jj-ai-commit --prompt "Emphasize breaking changes"

# Open editor after generating message
jj-ai-commit --edit

# List available models
jj-ai-commit -l
```

## License

MIT License - see [LICENSE](LICENSE) file for details.
