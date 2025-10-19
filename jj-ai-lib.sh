#!/bin/bash
# Shared library for jj AI commit message generation scripts

# Default model selection
# Returns the name of the preferred model to use
select_default_model() {
    local models
    models=$(llm models)

    # Check if we got any models
    if [ -z "$models" ]; then
        echo "Error: No LLM models found. Please install at least one model." >&2
        exit 1
    fi

    # Define preferred models in order of preference
    local preferred_models=(
        "ai-commit-message"
        "claude-3.5-sonnet"
        "gemini-2.0-flash-latest"
        "o3-mini"
        "deepseek-coder"
        "gpt-4o-mini"
    )

    # Try each preferred model in order
    for model in "${preferred_models[@]}"; do
        if echo "$models" | grep -q "$model"; then
            echo "$model"
            return 0
        fi
    done

    # If no preferred model is found, use the first available model
    echo "$models" | head -n 1
}

# Resolve model alias to actual model name for display
# Arguments:
#   $1 - model name (may be an alias)
# Returns: "alias: actual-model" or just the model name
resolve_model_display() {
    local model="$1"
    local model_display="$model"

    if [[ "$model" == "ai-commit-message" ]]; then
        local resolved_model
        resolved_model=$(llm aliases list 2>/dev/null | grep "^ai-commit-message" | sed 's/^ai-commit-message[[:space:]]*:[[:space:]]*//')
        if [[ -n "$resolved_model" ]]; then
            model_display="ai-commit-message: $resolved_model"
        fi
    fi

    echo "$model_display"
}

# Load additional instructions from global and project files
# Arguments:
#   $1 - repository root path
# Returns: Combined instructions from global and project files
load_additional_instructions() {
    local repo_root="$1"
    local instructions=""

    # Load global instructions
    local global_file="$HOME/.config/ai-commit-instructions"
    if [ -f "$global_file" ]; then
        instructions=$(cat "$global_file")
    fi

    # Load project-local instructions
    local project_file="$repo_root/.ai-commit-instructions"
    if [ -f "$project_file" ]; then
        if [ -n "$instructions" ]; then
            instructions="$instructions

"
        fi
        instructions="$instructions$(cat "$project_file")"
    fi

    echo "$instructions"
}

# Sanitize UTF-8 input by replacing invalid sequences
# Reads from stdin, writes sanitized output to stdout
sanitize_utf8() {
    # Try iconv first (faster), fall back to Python if not available
    if command -v iconv >/dev/null 2>&1; then
        # -c skips invalid sequences
        iconv -f UTF-8 -t UTF-8 -c
    else
        # Python fallback: replace invalid UTF-8 with replacement character
        python3 -c "
import sys
data = sys.stdin.buffer.read()
sys.stdout.write(data.decode('utf-8', errors='replace'))
"
    fi
}

# Generate a commit message from diff using AI
# Arguments:
#   $1 - model name
#   $2 - custom prompt (optional, can be empty)
#   $3 - current description (optional, can be empty)
# Reads diff from stdin
# Returns: Generated commit message
generate_commit_message() {
    local model="$1"
    local custom_prompt="$2"
    local current_desc="$3"

    # Read and sanitize diff from stdin
    local diff_content
    diff_content=$(sanitize_utf8)

    # Check if diff is empty
    if [ -z "$diff_content" ]; then
        echo "Error: No diff content provided" >&2
        return 1
    fi

    # Build the prompt based on whether custom prompt is provided
    local prompt_text
    if [[ -n "$custom_prompt" ]]; then
        prompt_text="Analyze these changes and create a commit message according to the following instructions:

Changes:
\`\`\`
$diff_content
\`\`\`"

        if [[ -n "$current_desc" ]]; then
            prompt_text="$prompt_text

Current description:
\`\`\`
$current_desc
\`\`\`"
        fi

        prompt_text="$prompt_text

Instructions:
\`\`\`
$custom_prompt
\`\`\`

Format the response as a conventional commit message with a brief title line followed by a more detailed description if needed.
Do not include a summary paragraph after any list of changes.

FORMATTING RULES:
- Commit messages are viewed as plain text, not rendered markdown
- Use backticks for \`code\`, \`filenames\`, and \`identifiers\`
- Do NOT use **bold** or *italic* markdown
- Write bullet lists as plain text with simple dashes (-)
- Keep formatting minimal and readable as plain text

GOOD EXAMPLE:
feat: Add gradient compression pipeline

- Implement bucket-based quantization codec
- Add compression ratio calculation in \`metrics.py\`
- Support 8-bit and 16-bit quantization modes
- Update documentation with usage examples

AVOID (too much markdown):
feat: Add gradient compression pipeline

- **Implement** bucket-based quantization codec
- Add compression ratio calculation in **metrics.py**
- Support **8-bit** and **16-bit** quantization modes
- Update **documentation** with usage examples

Don't include any other text in the response, just the commit message."
    else
        prompt_text="Analyze these changes and create a conventional commit message:

\`\`\`
$diff_content
\`\`\`"

        if [[ -n "$current_desc" ]]; then
            prompt_text="$prompt_text

Current description (if any):
\`\`\`
$current_desc
\`\`\`"
        fi

        prompt_text="$prompt_text

Format the response as a conventional commit message with a brief title line followed by a more detailed description if needed.
Do not include a summary paragraph after any list of changes.
Follow the conventional commit format (e.g., feat:, fix:, docs:, chore:, refactor:, test:, style:).

FORMATTING RULES:
- Commit messages are viewed as plain text, not rendered markdown
- Use backticks for \`code\`, \`filenames\`, and \`identifiers\`
- Do NOT use **bold** or *italic* markdown
- Write bullet lists as plain text with simple dashes (-)
- Keep formatting minimal and readable as plain text

GOOD EXAMPLE:
feat: Add gradient compression pipeline

- Implement bucket-based quantization codec
- Add compression ratio calculation in \`metrics.py\`
- Support 8-bit and 16-bit quantization modes
- Update documentation with usage examples

AVOID (too much markdown):
feat: Add gradient compression pipeline

- **Implement** bucket-based quantization codec
- Add compression ratio calculation in **metrics.py**
- Support **8-bit** and **16-bit** quantization modes
- Update **documentation** with usage examples

Don't include any other text in the response, just the commit message."
    fi

    # Generate commit message using llm
    # Pass prompt as argument, which may still be large but less likely to hit ARG_MAX
    # than including the diff in the argument
    local commit_msg
    commit_msg=$(echo "$prompt_text" | llm --model "$model")

    # Strip markdown code fences if present
    if [[ "$commit_msg" =~ ^\`\`\`.* ]] && [[ "$commit_msg" =~ \`\`\`$ ]]; then
        commit_msg=$(echo "$commit_msg" | sed -e '1s/^```.*//' -e '$s/```$//' | sed '/^$/d')
    fi

    echo "$commit_msg"
}

# Revise a commit description according to instructions using AI
# Arguments:
#   $1 - model name
#   $2 - revision prompt (instructions for how to revise)
#   $3 - additional instructions (optional, can be empty)
#   $4 - current description
# Returns: Revised commit description
generate_revision_message() {
    local model="$1"
    local revision_prompt="$2"
    local additional_instructions="$3"
    local current_desc="$4"

    # Check if current description is empty
    if [ -z "$current_desc" ]; then
        echo "Error: Cannot revise empty description" >&2
        return 1
    fi

    # Build the prompt
    local prompt_text="Revise the following commit description according to the instructions below.

Current description:
\`\`\`
$current_desc
\`\`\`

Revision instructions:
\`\`\`
$revision_prompt
\`\`\`"

    if [[ -n "$additional_instructions" ]]; then
        prompt_text="$prompt_text

Additional instructions:
\`\`\`
$additional_instructions
\`\`\`"
    fi

    prompt_text="$prompt_text

IMPORTANT:
- Maintain the conventional commit format (e.g., feat:, fix:, docs:, chore:, refactor:, test:, style:)
- Keep the same commit type unless the instructions explicitly ask to change it
- Apply the revision instructions while preserving the essential meaning
- Output only the revised commit message, nothing else

FORMATTING RULES:
- Commit messages are viewed as plain text, not rendered markdown
- Use backticks for \`code\`, \`filenames\`, and \`identifiers\`
- Do NOT use **bold** or *italic* markdown
- Write bullet lists as plain text with simple dashes (-)
- Keep formatting minimal and readable as plain text

Don't include any other text in the response, just the revised commit message."

    # Generate revised message using llm
    local revised_msg
    revised_msg=$(echo "$prompt_text" | llm --model "$model")

    # Strip markdown code fences if present
    if [[ "$revised_msg" =~ ^\`\`\`.* ]] && [[ "$revised_msg" =~ \`\`\`$ ]]; then
        revised_msg=$(echo "$revised_msg" | sed -e '1s/^```.*//' -e '$s/```$//' | sed '/^$/d')
    fi

    echo "$revised_msg"
}
