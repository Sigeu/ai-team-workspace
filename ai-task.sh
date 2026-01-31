#!/bin/bash

# Configuration
BASE_DIR="./workspaces/.ai_team"
REGISTRY_DIR="$BASE_DIR/registry"
TASKS_DIR="$BASE_DIR/tasks"

# Environment Check
if [ ! -d "$REGISTRY_DIR" ]; then
    echo "Error: AI Team Registry not found ($REGISTRY_DIR)."
    echo "Please start the Docker containers first: docker-compose up -d"
    exit 1
fi

echo "=== AI Team Task Dispatch System ==="

# Helper: Parse simple JSON fields using sed
# Usage: get_json_value "key" "file_path"
function get_json_value() {
    local key=$1
    local file=$2
    # Match "key": "value" pattern, extract value
    sed -n 's/.*"'"$key"'": *"\([^"]*\)".*/\1/p' "$file"
}

# 1. Get available Agent list (with health check)
echo "Scanning for online Agents..."
agents=()
display_names=()

i=1
# Enable nullglob to prevent error if no files exist
shopt -s nullglob
for f in "$REGISTRY_DIR"/*.json; do
    # Extract info using sed, removing dependency on jq
    name=$(get_json_value "name" "$f")
    container_id=$(get_json_value "container_id" "$f")
    
    if [ -z "$name" ]; then continue; fi

    # Health check: verify if container is actually running
    if [ -n "$container_id" ]; then
        if ! docker ps -q --no-trunc | grep -q "$container_id"; then
            echo "  [Warning] Found zombie node: $name (Container ${container_id:0:12} not running). Cleaning up..."
            rm "$f"
            continue
        fi
    fi

    # Format display
    name_upper=$(echo "$name" | tr '[:lower:]' '[:upper:]')
    echo "  [$i] 🟢 $name_upper (ID: ${container_id:0:12})"
    
    agents+=("$name")
    display_names+=("$name_upper")
    ((i++))
done
shopt -u nullglob

if [ ${#agents[@]} -eq 0 ]; then
    echo ""
    echo "❌ No active Agents found."
    echo "Possible reasons:"
    echo "1. Containers are not started or starting up (check with 'docker-compose ps')"
    echo "2. AI tools are installing (please wait a few seconds)"
    exit 1
fi

# 2. Select Assignee
echo ""
read -p "Select Task Assignee (Enter number): " agent_idx
if [[ ! "$agent_idx" =~ ^[0-9]+$ ]] || [ "$agent_idx" -lt 1 ] || [ "$agent_idx" -gt ${#agents[@]} ]; then
    echo "Invalid selection."
    exit 1
fi

selected_agent="${agents[$((agent_idx-1))]}"
selected_agent_display="${display_names[$((agent_idx-1))]}"
# Convert to lowercase for path
selected_agent_lower=$(echo "$selected_agent" | tr '[:upper:]' '[:lower:]')

# 3. Input Task Info
echo ""
echo "Creating task for $selected_agent_display..."
read -p "Enter Task Title: " title
echo "Enter Task Details (Press Ctrl+D when finished):"
details=$(cat)

# 4. Generate Task File
timestamp=$(date +%Y%m%d_%H%M%S)
# Simple filename cleaning, keep unicode, replace illegal chars with underscore
safe_title=$(echo "$title" | sed 's/[ \/\\:*?"<>|]/_/g' | cut -c 1-50)
task_filename="task_${timestamp}_${safe_title}.md"
task_path="$TASKS_DIR/$selected_agent_lower/$task_filename"

# Ensure directory exists
mkdir -p "$(dirname "$task_path")"

# Write file
cat > "$task_path" <<EOF
# Task: $title
## Status: [Pending]
## Reporter: User (Host)
## Priority: High
## Assignee: $selected_agent
## Project Directory: 

## Description
$details

## Collaboration Guide
1. You are the **Primary Owner** of this task.
2. Analyze the task difficulty. If help is needed, check other Agents in \`/workspaces/.ai_team/registry/\` and dispatch subtasks by creating task files.
3. Create or modify corresponding project code under \`/workspaces/\`.
EOF

echo ""
echo "✅ Task Published: $task_path"
echo "🚀 $selected_agent_display should receive the notification and start processing soon."
