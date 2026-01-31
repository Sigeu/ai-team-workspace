# AI 团队协作工作区 (AI Team Workspace)

本项目通过 Docker 构建了一个本地多智能体 AI 协作环境。你可以通过 Web 控制台或 CLI 向不同的 AI 智能体（如 Claude 和 Gemini）派发任务，它们将在共享的工作区内自主完成项目开发。

## 系统架构

系统由以下 Docker 服务组成：

*   **`web-console`**: 基于 Python FastAPI 的 Web 应用，作为管理后台。你可以：
    *   查看在线智能体。
    *   创建并派发任务。
    *   监控任务状态。
    *   打包下载项目文件。
*   **`claude-bot`**: 运行 `claude` CLI 的容器。它会监听自己的任务收件箱并执行指令。
*   **`gemini-bot`**: 运行 `gemini` CLI 的容器。工作原理与 Claude 机器人类似。
*   **`cli-proxy-api`**: API 代理服务，用于处理发往外部 AI 提供商（Anthropic, Google）的请求。

## 目录结构

*   **`config/`**: 智能体的配置文件目录。
*   **`proxy/`**: 代理服务的配置和日志。
*   **`web-console/`**: Web 控制台的源代码。
*   **`workspaces/`**: 智能体进行工作的共享目录。**注意：** 此目录下的内容被版本控制忽略。
    *   **`.ai_team/`**: 系统目录，包含任务收件箱、智能体注册表和日志。由系统自动创建。
*   **`ai-task.sh`**: 宿主机侧的 CLI 脚本，用于发布任务。
*   **`install-agents.sh`**: 智能体容器的入口脚本（负责安装工具、注册服务和监听任务）。

## 快速上手

### 前置条件

*   已安装 Docker 和 Docker Compose。

### 安装与配置

1.  **准备配置文件**:
    项目包含配置文件模板。你必须将它们拷贝为正式文件名，因为实际的配置文件已被 git 忽略（以保护密钥安全）。
    ```bash
    cp .env.example .env
    cp proxy/config.yaml.example proxy/config.yaml
    ```
    *   **关于工作区 (Workspaces)**: `workspaces/` 目录是实际的工作区域。此处创建的文件会被版本控制忽略，以保持仓库整洁。`.ai_team` 系统目录会在运行时自动生成。

2.  **身份认证**:
    你可以通过两种方式对 AI 智能体进行身份认证：

    *   **方案 A：使用 CLI Proxy API (推荐)**
        本项目已预配置与 [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) 配合使用。
        请参考 CLIProxyAPI 文档来配置 `proxy/config.yaml` 并管理账号。
        确保你的 `.env` 文件指向了代理服务的相关变量。

    *   **方案 B：使用 AI 工具原生登录**
        如果你希望使用 AI 工具自带的登录命令（例如 `claude login`, `gemini login`）：
        1.  `docker-compose.yml` 已将配置目录（如 `./config/claude`, `./config/gemini`）挂载到容器中。
        2.  以交互模式运行一次容器以完成登录流程。凭据将保存到挂载的宿主机目录中，并在重启后保持有效。
        ```bash
        # 以 Claude 为例
        docker-compose run --rm claude-bot bash
        # 在容器内部执行：
        claude login
        # 按照提示操作，完成后退出。凭据将保存在 ./config/claude 中。
        ```

3.  **启动服务**:
    ```bash
    docker-compose up -d
    ```

4.  **验证状态**:
    检查所有容器是否都在运行：
    ```bash
    docker-compose ps
    ```

### 使用方法

#### 方式 1：Web 控制台 (推荐)

1.  在浏览器中打开 `http://localhost:38317`。
2.  你将看到可用智能体列表和现有任务。
3.  通过表单创建新任务：
    *   **Agent**: 选择目标智能体 (如 CLAUDE, GEMINI)。
    *   **Title**: 任务的简要摘要。
    *   **Details**: 给 AI 的详细指令。
4.  智能体将领取任务，更新其状态，并在 `workspaces/` 目录下开始工作。

#### 方式 2：CLI 工具

你也可以直接从终端创建任务：

```bash
./ai-task.sh
```

按照交互式提示选择负责人并输入任务详情。

## 系统扩展

### 新增智能体 (Agent)

你可以通过增加容器来扩展团队规模。

1.  **更新 `docker-compose.yml`**:
    为新智能体添加服务定义。你可以参考 `claude-bot` 或 `gemini-bot` 的配置。
    *   确保定义了唯一的 `ROLE` 环境变量（例如 `ROLE=GPT4`）。
    *   挂载必要的配置卷。

2.  **更新 `install-agents.sh`**:
    该脚本在智能体容器启动时运行。你必须添加逻辑以支持新角色：
    *   添加对新 `ROLE` 的判断。
    *   添加安装该智能体特定 CLI 工具的命令（例如 `npm install -g <tool-name>`）。

3.  **重启系统**:
    重新构建并启动容器以应用更改。
    ```bash
    docker-compose up -d --build
    ```

## 任务格式

任务以 Markdown 文件形式存储在 `workspaces/.ai_team/tasks/<agent>/`。系统使用特定的标题行来跟踪状态：

```markdown
# Task: <任务标题>
## Status: [Pending]
## Assignee: <负责人名称>
## Project Directory: <可选的项目目录>

## Description
... 任务详细描述 ...
```

智能体在工作过程中会自动将状态更新为 `[In Progress]` (进行中)，完成后更新为 `[Completed]` (已完成)。
