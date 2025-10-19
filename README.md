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
jj config set --user 'aliases.ai-revise' '["util", "exec", "--", "jj-ai-revise"]'
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

### `jj-file-untrack-ignored`
Automatically stops tracking working copy files that have become ignored by `.gitignore`. Useful after updating ignore rules so that generated artifacts disappear from `jj status` without manually untracking each file.

```bash
# Untrack all tracked files now ignored by .gitignore
jj-file-untrack-ignored

# Preview what would be untracked
jj-file-untrack-ignored --dry-run
```

### `jj-file-delete`
Remove files matching glob patterns from all revisions in a revset. Useful for removing accidentally committed files, build artifacts, or sensitive data from multiple revisions at once.

```bash
# Remove a specific file from all revisions in pk::
jj-file-delete -r "pk::" parallel-differential-coding-slepian-wolf-analysis.md

# Remove all .md files from revisions
jj-file-delete -r "main..@" "*.md"

# Remove multiple patterns with dry-run
jj-file-delete -n -r "pk::" "*.log" "*.aux" "build/**"

# Remove files from specific revisions
jj-file-delete -r "@- | @" temp.txt
```

The script processes revisions in topological order and skips any revisions where the file patterns don't match. Descendant revisions are automatically rebased as needed.

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

#### Customizing AI Instructions

You can provide additional instructions to guide the AI's commit message generation using instruction files. Instructions from multiple sources are combined:

1. **Global instructions** (`~/.config/ai-commit-instructions`) - applies to all repositories
2. **Per-project instructions** (`.ai-commit-instructions` in repo root) - applies only to the current project
3. **Command-line prompt** (`--prompt` option) - applies to a single invocation

**Example global instructions** (`~/.config/ai-commit-instructions`):
```
Use conventional commit format.
Keep commit titles under 50 characters.
Use imperative mood in the commit title.
```

**Example project-specific instructions** (`.ai-commit-instructions`):
```
Don't mention "Slepian-Wolf" in commit messages since it's implied by the project context.
Focus on what changed, not the project domain.
Emphasize performance implications of algorithmic changes.
```

The `.ai-commit-instructions` file can be version-controlled and shared with your team to ensure consistent commit message style across all contributors.

### `jj-ai-describe`
Generates conventional commit messages for Jujutsu revisions using AI. Analyzes the changes in each revision and creates descriptive commit messages following conventional commit format. Accepts multiple revset arguments, and each revset is expanded to individual revisions with unique messages generated for each.

**By default, only revisions with empty descriptions are processed.** Use `--replace` to process all revisions regardless of their current description.

```bash
# Generate and apply message for current working copy (if empty)
jj-ai-describe
# Or with the alias: jj ai-describe

# Generate message for a specific revision (if empty)
jj-ai-describe abc123

# Generate messages for multiple revisions (only those with empty descriptions)
jj-ai-describe @- @                    # Two specific revisions
jj-ai-describe "main..@"               # All revisions from main to @
jj-ai-describe @ "fork..@-"            # @ plus all revisions in range

# Replace existing descriptions (even non-empty ones)
jj-ai-describe --replace "main..@"

# Preview messages without applying them
jj-ai-describe -n "main..@"            # Dry-run for all revisions in range

# Use a specific LLM model
jj-ai-describe --model gpt-4 @- @

# Provide additional instructions for the messages
jj-ai-describe --prompt "Focus on the performance improvements" "main..@"
```

**Note**: When processing multiple revisions, the script stops on the first error. In dry-run mode, all messages are generated first and then displayed together. If a revset contains no revisions with empty descriptions, the command exits with an error (unless `--replace` is used).

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

### `jj-ai-revise`
Revises existing commit descriptions according to instructions using AI. This command modifies existing descriptions based on a prompt, without looking at the actual code changes. Useful for applying consistent style changes across multiple commits, such as removing markdown formatting, making descriptions more concise, or removing redundant information.

**Only revisions with non-empty descriptions are processed.** Revisions with empty descriptions are automatically skipped.

```bash
# Revise descriptions to remove bold markdown
jj-ai-revise --prompt "Remove bold markup" "main..@"
# Or with the alias: jj ai-revise --prompt "Remove bold markup" "main..@"

# Make descriptions more concise
jj-ai-revise --prompt "Be more concise" @-

# Remove redundant project-specific mentions
jj-ai-revise --prompt "Don't mention Slepian-Wolf; it's implicit" "pk::"

# Preview revisions without applying them
jj-ai-revise -n --prompt "Use imperative mood" "main..@"

# Revise multiple specific revisions
jj-ai-revise --prompt "Remove technical jargon" @ @- @--

# Use a specific LLM model
jj-ai-revise --model gpt-4 --prompt "Simplify language" "main..@"
```

**Example use cases:**
- Remove markdown formatting (bold, italics) from commit messages
- Make commit messages more concise or verbose
- Remove project-specific terminology that's implicit in context
- Change tone or style (e.g., imperative mood vs. past tense)
- Fix grammar or spelling consistently across multiple commits

**Note**: The revision prompt is combined with any instructions from `.ai-commit-instructions` files, so project-specific conventions are automatically applied.

## License

MIT License - see [LICENSE](LICENSE) file for details.
