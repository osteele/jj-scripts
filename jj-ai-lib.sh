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

    # If no preferred model is found, ask the user to configure one
    echo "Error: No preferred LLM model found. Set a default with:" >&2
    echo "  llm aliases set ai-commit-message <model-name>" >&2
    exit 1
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

# Normalize max-bytes setting, falling back to a default if invalid
normalize_max_bytes() {
    local value="$1"
    local default_value="$2"

    if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt 0 ]; then
        echo "$value"
    else
        echo "$default_value"
    fi
}

# Detect whether an LLM error indicates the prompt is too long
is_prompt_too_long() {
    local message="$1"
    echo "$message" | tr '[:upper:]' '[:lower:]' | grep -qE 'input is too long|too long for requested model|prompt.*too long|maximum context|context.*(length|window)'
}

# Truncate diff content for prompt size, keeping head and tail
# Sets AI_COMMIT_TRUNCATED and AI_COMMIT_TRUNCATION_NOTE
truncate_diff_for_prompt() {
    local diff="$1"
    local max_bytes="$2"

    AI_COMMIT_TRUNCATED=false
    AI_COMMIT_TRUNCATION_NOTE=""

    if (( max_bytes <= 0 )); then
        echo "$diff"
        return 0
    fi

    local diff_size=${#diff}
    if (( diff_size <= max_bytes )); then
        echo "$diff"
        return 0
    fi

    local head_bytes=$(( max_bytes * 2 / 3 ))
    local tail_bytes=$(( max_bytes - head_bytes ))
    local head
    local tail
    head=$(printf '%s' "$diff" | head -c "$head_bytes")
    tail=$(printf '%s' "$diff" | tail -c "$tail_bytes")
    local omitted=$(( diff_size - head_bytes - tail_bytes ))

    AI_COMMIT_TRUNCATED=true
    AI_COMMIT_TRUNCATION_NOTE="Diff truncated from ${diff_size} bytes to ${max_bytes} bytes (${omitted} bytes omitted)."

    printf '%s\n\n[... %d bytes truncated ...]\n\n%s' "$head" "$omitted" "$tail"
}

# Build the LLM prompt for commit message generation
build_commit_prompt() {
    local diff_content="$1"
    local custom_prompt="$2"
    local current_desc="$3"
    local truncation_note="$4"
    local note_block=""

    if [[ -n "$truncation_note" ]]; then
        note_block="NOTE: $truncation_note"
    fi

    if [[ -n "$custom_prompt" ]]; then
        printf '%s\n\n' "Analyze these changes and create a commit message according to the following instructions:"
        if [[ -n "$note_block" ]]; then
            printf '%s\n\n' "$note_block"
        fi
        printf 'Changes:\n```\n%s\n```\n' "$diff_content"
        if [[ -n "$current_desc" ]]; then
            printf '\nCurrent description:\n```\n%s\n```\n' "$current_desc"
        fi
        printf '\nInstructions:\n```\n%s\n```\n\n' "$custom_prompt"
        printf '%s\n' "Format the response as a conventional commit message with a brief title line followed by a more detailed description if needed."
        printf '%s\n\n' "Do not include a summary paragraph after any list of changes."
        printf '%s\n\n' "$_FORMAT_RULES"
        printf '%s' "Don't include any other text in the response, just the commit message."
    else
        printf '%s\n\n' "Analyze these changes and create a conventional commit message:"
        if [[ -n "$note_block" ]]; then
            printf '%s\n\n' "$note_block"
        fi
        printf '```\n%s\n```\n' "$diff_content"
        if [[ -n "$current_desc" ]]; then
            printf '\nCurrent description (if any):\n```\n%s\n```\n' "$current_desc"
        fi
        printf '\n%s\n' "Format the response as a conventional commit message with a brief title line followed by a more detailed description if needed."
        printf '%s\n' "Do not include a summary paragraph after any list of changes."
        printf '%s\n\n' "Follow the conventional commit format (e.g., feat:, fix:, docs:, chore:, refactor:, test:, style:)."
        printf '%s\n\n' "$_FORMAT_RULES"
        printf '%s' "Don't include any other text in the response, just the commit message."
    fi
}

# Shared formatting rules for commit message prompts
_FORMAT_RULES='FORMATTING RULES:
- Commit messages are viewed as plain text, not rendered markdown
- Use backticks for `code`, `filenames`, and `identifiers`
- Do NOT use **bold** or *italic* markdown
- Write bullet lists as plain text with simple dashes (-)
- Keep formatting minimal and readable as plain text

GOOD EXAMPLE:
feat: Add gradient compression pipeline

- Implement bucket-based quantization codec
- Add compression ratio calculation in `metrics.py`
- Support 8-bit and 16-bit quantization modes
- Update documentation with usage examples

AVOID (too much markdown):
feat: Add gradient compression pipeline

- **Implement** bucket-based quantization codec
- Add compression ratio calculation in **metrics.py**
- Support **8-bit** and **16-bit** quantization modes
- Update **documentation** with usage examples'

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

    local prompt_text
    local max_bytes
    local fallback_bytes
    max_bytes=$(normalize_max_bytes "${AI_COMMIT_MAX_DIFF_BYTES:-}" 200000)
    fallback_bytes=$(normalize_max_bytes "${AI_COMMIT_FALLBACK_DIFF_BYTES:-}" 40000)
    if (( fallback_bytes >= max_bytes )); then
        fallback_bytes=$(( max_bytes / 2 ))
    fi

    local truncated_diff
    local truncation_note=""
    local used_fallback=false

    truncated_diff=$(truncate_diff_for_prompt "$diff_content" "$max_bytes")
    if [[ "$AI_COMMIT_TRUNCATED" == "true" ]]; then
        truncation_note="$AI_COMMIT_TRUNCATION_NOTE"
    fi
    prompt_text=$(build_commit_prompt "$truncated_diff" "$custom_prompt" "$current_desc" "$truncation_note")

    # Generate commit message using llm
    # Pass prompt as argument, which may still be large but less likely to hit ARG_MAX
    # than including the diff in the argument
    local commit_msg
    local llm_exit_code
    commit_msg=$(echo "$prompt_text" | llm --model "$model" 2>&1)
    llm_exit_code=$?
    if [[ $llm_exit_code -ne 0 ]]; then
        if is_prompt_too_long "$commit_msg" && (( fallback_bytes < max_bytes )); then
            truncated_diff=$(truncate_diff_for_prompt "$diff_content" "$fallback_bytes")
            truncation_note=""
            if [[ "$AI_COMMIT_TRUNCATED" == "true" ]]; then
                truncation_note="$AI_COMMIT_TRUNCATION_NOTE"
            fi
            prompt_text=$(build_commit_prompt "$truncated_diff" "$custom_prompt" "$current_desc" "$truncation_note")
            commit_msg=$(echo "$prompt_text" | llm --model "$model" 2>&1)
            llm_exit_code=$?
            used_fallback=true
        fi
        if [[ $llm_exit_code -ne 0 ]]; then
            echo "$commit_msg" >&2
            return 1
        fi
    fi
    if [[ "$AI_COMMIT_TRUNCATED" == "true" ]]; then
        if [[ "$used_fallback" == "true" ]]; then
            echo "Warning: $AI_COMMIT_TRUNCATION_NOTE (after retry). Set AI_COMMIT_FALLBACK_DIFF_BYTES to adjust." >&2
        else
            echo "Warning: $AI_COMMIT_TRUNCATION_NOTE Set AI_COMMIT_MAX_DIFF_BYTES to adjust." >&2
        fi
    fi

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

$_FORMAT_RULES

Don't include any other text in the response, just the revised commit message."

    # Generate revised message using llm
    local revised_msg
    local llm_exit_code
    revised_msg=$(echo "$prompt_text" | llm --model "$model")
    llm_exit_code=$?
    if [[ $llm_exit_code -ne 0 ]]; then
        echo "$revised_msg" >&2
        return 1
    fi

    # Strip markdown code fences if present
    if [[ "$revised_msg" =~ ^\`\`\`.* ]] && [[ "$revised_msg" =~ \`\`\`$ ]]; then
        revised_msg=$(echo "$revised_msg" | sed -e '1s/^```.*//' -e '$s/```$//' | sed '/^$/d')
    fi

    echo "$revised_msg"
}
