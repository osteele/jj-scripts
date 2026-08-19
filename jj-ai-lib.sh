#!/bin/bash
# Adapter functions for the shared ai-commit executable.

find_ai_commit_engine() {
    if [[ -n "${AI_COMMIT_MESSAGE:-}" && -x "$AI_COMMIT_MESSAGE" ]]; then
        printf '%s\n' "$AI_COMMIT_MESSAGE"
        return 0
    fi

    local sibling_engine
    sibling_engine="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../ai-commit/ai-commit-message"
    if [[ -x "$sibling_engine" ]]; then
        printf '%s\n' "$sibling_engine"
        return 0
    fi

    local installed_engine
    installed_engine=$(command -v ai-commit-message 2>/dev/null || true)
    if [[ -n "$installed_engine" ]]; then
        printf '%s\n' "$installed_engine"
        return 0
    fi

    echo "Error: ai-commit is required. Install it and add ai-commit-message to PATH." >&2
    return 1
}

select_default_model() {
    "$(find_ai_commit_engine)" default-model
}

resolve_model_display() {
    "$(find_ai_commit_engine)" model-display "$1"
}

load_additional_instructions() {
    "$(find_ai_commit_engine)" instructions "$1"
}

validate_narration_policy() {
    case "$1" in
        auto|always|never) return 0 ;;
        *)
            echo "Error: --narrate-diff must be auto, always, or never" >&2
            return 1
            ;;
    esac
}

generate_commit_message() {
    local model="$1"
    local custom_prompt="$2"
    local current_desc="$3"
    local narration_policy="${4:-${AI_COMMIT_NARRATE_DIFF:-never}}"
    local -a args=(generate --model "$model" --narrate-diff "$narration_policy")
    if [[ -n "$custom_prompt" ]]; then
        args+=(--prompt "$custom_prompt")
    fi
    if [[ -n "$current_desc" ]]; then
        args+=(--current-description "$current_desc")
    fi
    "$(find_ai_commit_engine)" "${args[@]}"
}
generate_split_plan() {
    local model="$1"
    local custom_prompt="$2"
    local files_from="$3"
    local narration_policy="${4:-${AI_COMMIT_NARRATE_DIFF:-never}}"
    local -a args=(split --model "$model" --narrate-diff "$narration_policy" --files-from "$files_from")
    if [[ -n "$custom_prompt" ]]; then
        args+=(--prompt "$custom_prompt")
    fi
    "$(find_ai_commit_engine)" "${args[@]}"
}

generate_revision_message() {
    local model="$1"
    local revision_prompt="$2"
    local additional_instructions="$3"
    local current_desc="$4"
    local -a args=(revise --model "$model" --prompt "$revision_prompt" --current-description "$current_desc")
    if [[ -n "$additional_instructions" ]]; then
        args+=(--instructions "$additional_instructions")
    fi
    "$(find_ai_commit_engine)" "${args[@]}"
}
