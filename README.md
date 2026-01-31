# AI Team Workspace

This project sets up a local multi-agent AI collaboration environment using Docker. It allows you to dispatch tasks to different AI agents (like Claude and Gemini) via a Web Console or a CLI, and have them autonomously work on projects within a shared workspace.

## Architecture

The system consists of the following Docker services:

*   **`web-console`**: A Python FastAPI web application acting as the dashboard. It allows you to:
    *   View online agents.
    *   Create and dispatch tasks.
    *   Monitor task status.
    *   Download project files.
*   **`claude-bot`**: A container running the `claude` CLI agent. It monitors its task inbox and executes instructions.
*   **`gemini-bot`**: A container running the `gemini` CLI agent. It operates similarly to the Claude bot.
*   **`cli-proxy-api`**: An API proxy service to handle requests to external AI providers (Anthropic, Google).

## Directory Structure

*   **`config/`**: Configuration files for agents.
*   **`proxy/`**: Configuration and logs for the proxy service.
*   **`web-console/`**: Source code for the web dashboard.
*   **`workspaces/`**: The shared directory where agents perform their work. **Note:** Contents here are ignored by version control.
    *   **`.ai_team/`**: System directory containing task inboxes, agent registry, and logs. Automatically created by the system.
*   **`ai-task.sh`**: Host-side CLI script to create tasks.
*   **`install-agents.sh`**: The entrypoint script for agent containers (handles installation, registration, and monitoring).

## Getting Started

### Prerequisites

*   Docker and Docker Compose installed.

### Setup & Configuration

1.  **Prepare Configuration Files**:
    The project includes template files for configuration. You must copy them to their active filenames because the actual configuration files are git-ignored (to protect secrets).
    ```bash
    cp .env.example .env
    cp proxy/config.yaml.example proxy/config.yaml
    ```
    *   **Note on Workspaces**: The `workspaces/` directory is the active working area. Files created here are ignored by version control to keep the repository clean. The `.ai_team` system directory is automatically generated at runtime.

2.  **Authentication**:
    You have two options for authenticating your AI agents:

    *   **Option A: Using CLI Proxy API (Recommended)**
        This project is configured to work with [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI).
        Refer to the CLIProxyAPI documentation for setting up your `proxy/config.yaml` and managing accounts.
        Ensure your `.env` file points to your proxy service variables.

    *   **Option B: Native CLI Login**
        If you prefer to use the AI tools' native login (e.g., `claude login`, `gemini login`):
        1.  The `docker-compose.yml` mounts configuration directories (e.g., `./config/claude`, `./config/gemini`) into the containers.
        2.  Run the container interactively **once** to perform the login flow. The credentials will be saved to the mounted host directory and persist across restarts.
        ```bash
        # Example for Claude
        docker-compose run --rm claude-bot bash
        # Inside container:
        claude login
        # Follow prompts, then exit. Credentials are saved in ./config/claude
        ```

3.  **Start Services**:
    ```bash
    docker-compose up -d
    ```

4.  **Verify Status**:
    Check if all containers are running:
    ```bash
    docker-compose ps
    ```

### Usage

#### Option 1: Web Console (Recommended)

1.  Open your browser and navigate to `http://localhost:38317`.
2.  You will see the list of available agents and existing tasks.
3.  Use the form to create a new task:
    *   **Agent**: Select the target agent (e.g., CLAUDE, GEMINI).
    *   **Title**: A brief summary of the task.
    *   **Details**: Detailed instructions for the AI.
4.  The agent will pick up the task, update its status, and start working in the `workspaces/` directory.

#### Option 2: CLI Tool

You can also create tasks directly from your terminal:

```bash
./ai-task.sh
```

Follow the interactive prompts to select an agent and input task details.

## Extending the System

### Adding New Agents

You can expand the team by adding more AI agents (containers).

1.  **Update `docker-compose.yml`**:
    Add a new service definition for the new agent. You can copy the configuration of `claude-bot` or `gemini-bot`.
    *   Ensure you define a unique `ROLE` environment variable (e.g., `ROLE=GPT4`).
    *   Mount the necessary config volumes.

2.  **Update `install-agents.sh`**:
    This script runs inside the agent containers at startup. You must add logic to support the new agent:
    *   Add a check for the new `ROLE`.
    *   Add the command to install the specific CLI tool for that agent (e.g., `npm install -g <tool-name>`) if it's not already in the base image.

3.  **Restart**:
    Rebuild and restart the containers to apply changes.
    ```bash
    docker-compose up -d --build
    ```

## Task Format

Tasks are stored as Markdown files in `workspaces/.ai_team/tasks/<agent>/`. The system uses specific headers to track state:

```markdown
# Task: <Title>
## Status: [Pending]
## Assignee: <Agent Name>
## Project Directory: <Optional Path>

## Description
...
```

The Agent will automatically update the status to `[In Progress]` and then `[Completed]` as it works.