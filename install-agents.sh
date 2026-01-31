#!/bin/bash

# Base Configuration
base_dir="/workspaces/.ai_team"
logs_dir="$base_dir/logs"
registry_dir="$base_dir/registry"

# Determine current Agent's inbox based on environment variable
agent_role_lower=$(echo "$ROLE" | tr '[:upper:]' '[:lower:]')
agent_inbox="$base_dir/tasks/$agent_role_lower"
rules_file="/home/node/.${agent_role_lower}/${ROLE}.md"

mkdir -p "$agent_inbox" "$logs_dir" "$registry_dir"

echo "=== $ROLE Agent Startup Program ==="

# Ensure PATH includes NPM global directory
export PATH="/home/node/.npm-global/bin:$PATH"
export FORCE_COLOR=1
export CI=true

# --- 0. Lifecycle Management ---
registry_file="$registry_dir/${ROLE}.json"
monitor_pid=""

function cleanup() {
    echo "=== [System Signal] Deregistering service: $ROLE ==="
    rm -f "$registry_file"
    if [ -n "$monitor_pid" ]; then
        kill "$monitor_pid" 2>/dev/null
    fi
    echo "Service deregistered."
    exit 0
}

trap cleanup EXIT SIGTERM SIGINT

# --- 1. Check and Install Tools (Preparation Phase) ---
if [ "$ROLE" == "CLAUDE" ]; then
    if ! command -v claude &> /dev/null; then
        echo "Claude Code not detected, installing..."
        npm install -g @anthropic-ai/claude-code@latest
    else
        echo "Claude Code is ready"
    fi
elif [ "$ROLE" == "GEMINI" ]; then
    if ! command -v gemini &> /dev/null; then
        echo "Gemini CLI not detected, installing..."
        npm install -g @google/gemini-cli@latest
    else
        echo "Gemini CLI is ready"
    fi
fi

# 2. Sync Rules File
if [ -f "$rules_file" ]; then
    cp "$rules_file" "/workspaces/${ROLE}.md"
fi

# --- 3. Register Service (Ready Phase) ---
container_id=$(hostname)
echo "{\"name\": \"$ROLE\", \"inbox\": \"/workspaces/.ai_team/tasks/$agent_role_lower\", \"status\": \"online\", \"container_id\": \"$container_id\"}" > "$registry_file"
echo ">>> Service ready and registered: $registry_file (CID: $container_id)"

# --- 4. Task Processing Logic ---
function run_agent() {
    local task_file=$1
    
    # === Critical Fix: Loop Prevention Check ===
    # Only execute if file contains "## Status: [Pending]"
    # If it is [In Progress] or [Completed], ignore directly
    if ! grep -q "## Status: \[Pending\]" "$task_file"; then
        # Read current status for logging
        local current_status=$(grep -m 1 "## Status:" "$task_file" | awk -F'[][]' '{print $2}')
        echo "[$(date)] Ignoring non-pending task: $(basename "$task_file") (Current Status: $current_status)"
        return
    fi
    # ==============================

    local task_filename=$(basename "$task_file")
    local log_file="$logs_dir/${ROLE}_$(date +%Y%m%d_%H%M%S)_${task_filename}.log"

    local prompt="[System Instruction] 1. Read and follow /workspaces/${ROLE}.md. 2. Process task file: $task_file. 3. Change task status to [In Progress]. 4. Enter the specified project directory to work according to the task description. 5. Upon completion, change status to [Completed] and stop operation."

    echo "[$(date)] Start processing task: $task_filename" | tee -a "$log_file"
    echo "[$(date)] Debug: User=$(whoami)" | tee -a "$log_file"

    if [ "$ROLE" == "CLAUDE" ]; then
        script -a -q -c "timeout 900 claude --verbose --dangerously-skip-permissions -p '$prompt'" "$log_file" < /dev/null > /dev/null
        exit_code=$?
    elif [ "$ROLE" == "GEMINI" ]; then
        timeout 900 stdbuf -oL -eL gemini --yolo -p "$prompt" >> "$log_file" 2>&1
        exit_code=$?
    fi
    
    echo "[$(date)] Task finished: $task_filename (Exit Code: $exit_code)" | tee -a "$log_file"
}

# --- 5. Monitoring Logic ---
echo "$ROLE Monitoring service running: $agent_inbox"

(
    # Still monitor create and moved_to
    # Because Web Console writing new file counts as create
    # At this time file status must be [Pending]
    # If AI changes status (might trigger moved_to), grep check in run_agent will intercept it, preventing infinite loop
    inotifywait -m -q -e create -e moved_to --format '%w%f' "$agent_inbox" | while read -r new_task_file;
    do
        if [ -f "$new_task_file" ]; then
            echo "[$(date)] Detected new file event: $new_task_file"
            run_agent "$new_task_file"
        fi
    done
) &

monitor_pid=$!
wait "$monitor_pid"
