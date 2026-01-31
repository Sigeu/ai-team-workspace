from fastapi import FastAPI, Request, Form, BackgroundTasks
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi.responses import RedirectResponse, FileResponse
import uvicorn
import os
import json
import glob
import datetime
import re
import shutil

app = FastAPI()

# Mount static files and templates
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# Path configuration
WORKSPACES_DIR = "/workspaces"
BASE_DIR = os.path.join(WORKSPACES_DIR, ".ai_team")
REGISTRY_DIR = os.path.join(BASE_DIR, "registry")
TASKS_DIR = os.path.join(BASE_DIR, "tasks")

# i18n Configuration
TRANSLATIONS = {
    "en": {
        "lang": "en",
        "title": "AI Team Console",
        "subtitle": "Intelligent Collaboration Factory",
        "new_task_btn": "New Task",
        "online_agents": "Online Agents",
        "no_agents": "No active agents found. Check Docker containers.",
        "task_board": "Task Board",
        "th_status": "Status",
        "th_title": "Task Title",
        "th_assignee": "Assignee",
        "th_project": "Project",
        "th_action": "Action",
        "status_completed": "Completed",
        "status_in_progress": "In Progress",
        "details_link": "Details",
        "modal_title": "Create New Task",
        "label_assignee": "Assignee",
        "label_title": "Task Title",
        "label_details": "Description",
        "btn_submit": "Submit",
        "btn_cancel": "Cancel",
        "back_to_console": "Back to Console",
        "task_detail_title": "Task Details",
        "download_title": "Download Project Source",
        "status_pending": "Pending",
        "unknown": "Unknown",
        "lang_select": "Language"
    },
    "zh": {
        "lang": "zh",
        "title": "AI Team 控制台",
        "subtitle": "智能协作开发工厂",
        "new_task_btn": "发布新任务",
        "online_agents": "在线 Agents",
        "no_agents": "暂无在线 Agent。请检查 Docker 容器状态。",
        "task_board": "任务看板",
        "th_status": "状态",
        "th_title": "任务标题",
        "th_assignee": "负责人",
        "th_project": "关联项目",
        "th_action": "操作",
        "status_completed": "已完成",
        "status_in_progress": "进行中",
        "details_link": "详情",
        "modal_title": "发布新任务",
        "label_assignee": "负责人",
        "label_title": "任务标题",
        "label_details": "详细描述",
        "btn_submit": "发布任务",
        "btn_cancel": "取消",
        "back_to_console": "返回控制台",
        "task_detail_title": "任务详情",
        "download_title": "下载项目源码",
        "status_pending": "待处理",
        "unknown": "未知",
        "lang_select": "语言"
    }
}

def get_trans(request: Request):
    # 1. Check Cookie
    cookie_lang = request.cookies.get("lang")
    if cookie_lang in TRANSLATIONS:
        return TRANSLATIONS[cookie_lang]
    
    # 2. Check Header
    accept_language = request.headers.get("accept-language", "")
    if "zh" in accept_language.lower():
        return TRANSLATIONS["zh"]
    return TRANSLATIONS["en"]

# Route: Set Language
@app.get("/set_lang")
async def set_lang(request: Request, lang: str):
    referer = request.headers.get("referer", "/")
    response = RedirectResponse(url=referer)
    response.set_cookie(key="lang", value=lang)
    return response

# Helper: Parse Markdown task file
def parse_task_file(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        filename = os.path.basename(filepath)
        agent = os.path.basename(os.path.dirname(filepath))
        
        # Extract title (First line # Task: ...)
        title_match = re.search(r'^# (?:Task|任务):\s*(.*)$', content, re.MULTILINE)
        title = title_match.group(1) if title_match else filename
        
        # Extract status (## Status: [...])
        status_match = re.search(r'^## (?:Status|状态):\s*\[(.*?)\]', content, re.MULTILINE)
        status = status_match.group(1) if status_match else "Unknown"
        
        # Extract project directory (## Project Directory: ...)
        project_match = re.search(r'^## (?:Project Directory|项目目录):\s*(.*)$', content, re.MULTILINE)
        project_path = project_match.group(1).strip() if project_match else None
        
        return {
            "filename": filename,
            "filepath": filepath,
            "agent": agent,
            "title": title,
            "status": status,
            "project_path": project_path,
            "mtime": os.path.getmtime(filepath)
        }
    except Exception as e:
        print(f"Error parsing {filepath}: {e}")
        return None

# Route: Dashboard
@app.get("/")
async def index(request: Request):
    trans = get_trans(request)
    # 1. Get online Agents
    agents = []
    if os.path.exists(REGISTRY_DIR):
        for f in glob.glob(os.path.join(REGISTRY_DIR, "*.json")):
            try:
                with open(f, 'r') as jf:
                    data = json.load(jf)
                    agents.append(data)
            except:
                pass
    
    # 2. Get all tasks
    tasks = []
    if os.path.exists(TASKS_DIR):
        for agent_dir in glob.glob(os.path.join(TASKS_DIR, "*")):
            if os.path.isdir(agent_dir):
                for task_file in glob.glob(os.path.join(agent_dir, "*.md")):
                    task_info = parse_task_file(task_file)
                    if task_info:
                        tasks.append(task_info)
    
    # Sort by time descending
    tasks.sort(key=lambda x: x['mtime'], reverse=True)
    
    return templates.TemplateResponse("index.html", {
        "request": request, 
        "agents": agents, 
        "tasks": tasks,
        "trans": trans
    })

# Route: Create Task
@app.post("/create_task")
async def create_task(agent: str = Form(...), title: str = Form(...), details: str = Form(...)):
    agent_lower = agent.lower()
    target_dir = os.path.join(TASKS_DIR, agent_lower)
    os.makedirs(target_dir, exist_ok=True)
    
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    # Allow unicode, only replace filesystem illegal chars (\ / : * ? " < > |) and spaces
    safe_title = re.sub(r'[\\/*?:"<>|\s]', '_', title)[:50]
    filename = f"task_{timestamp}_{safe_title}.md"
    filepath = os.path.join(target_dir, filename)
    
    content = f"""# Task: {title}
## Status: [Pending]
## Reporter: WebConsole
## Priority: High
## Assignee: {agent}
## Project Directory: 

## Description
{details}

## Collaboration Guide
1. You are the **Primary Owner** of this task.
2. Analyze the difficulty. If necessary, find collaborators via the registry.
3. Create or modify code under `/workspaces/`.
"""
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
        
    return RedirectResponse(url="/", status_code=303)

# Route: View Task Details
@app.get("/task/{agent}/{filename}")
async def view_task(request: Request, agent: str, filename: str):
    trans = get_trans(request)
    filepath = os.path.join(TASKS_DIR, agent, filename)
    if not os.path.exists(filepath):
        return "Task not found"
        
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        
    return templates.TemplateResponse("task_detail.html", {
        "request": request,
        "content": content,
        "filename": filename,
        "trans": trans
    })

# Route: Download Project
@app.get("/download_project")
async def download_project(path: str, background_tasks: BackgroundTasks):
    # Security check
    if not path.startswith("/workspaces/"):
        return "Invalid path"
    
    if not os.path.exists(path):
        return "Path not found"
        
    # Create temporary zip
    zip_filename = f"{os.path.basename(path)}.zip"
    zip_path = f"/tmp/{zip_filename}"
    
    shutil.make_archive(zip_path.replace('.zip', ''), 'zip', path)
    
    # Background task to remove the file
    background_tasks.add_task(os.remove, zip_path)

    return FileResponse(zip_path, filename=zip_filename)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=38317)
