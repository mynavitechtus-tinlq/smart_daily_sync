# Plan Thực Hiện: Slack Report & Backlog Analysis System

## 📋 Tổng Quan Cách Làm

Hệ thống này được triển khai theo mô hình **event-driven architecture** với các thành phần chính:
1. **Slack Event Listener** → nhận message từ Slack Events API
2. **Backlog Connectors** (GitHub, Nulab Backlog) → tìm kiếm & quản lý issue
3. **AI Analysis Service** (Gemini) → phân tích intent, sentiment, suggestion
4. **Action Engine** → thực thi action (post Slack, create/update issue)
5. **Public API** → cung cấp endpoints để tích hợp bên ngoài

---

## 🏗️ Kiến Trúc Hệ Thống

```
┌────────────────────────────────────────────────────────────────┐
│                      SLACK WORKSPACE                           │
│  User triggers: /sprint-report /daily-report /backlog-status   │
│                                                                │
│         /sprint-report [sprint_name] [project]                │
└──────────────────────────┬─────────────────────────────────────┘
                           │
                           ▼
          ┌────────────────────────────────────┐
          │  PUBLIC API ENDPOINT (NO AUTH)     │
          │  POST /api/v1/slack/slash-command  │
          │  - Receive slash command payload   │
          │  - Extract command & parameters    │
          │  - Route to handler                │
          └────────────┬──────────────────────┘
                       │
          ┌────────────┴────────────────┐
          │                             │
          ▼                             ▼
    ┌─────────────────┐    ┌──────────────────────┐
    │ Slash Command   │    │ Command Dispatcher   │
    │ Handler         │    │ - sprint-report      │
    │ - Validate cmd  │    │ - daily-report       │
    │ - Extract args  │    │ - backlog-status     │
    │ - Process async │    │ - team-velocity      │
    └────────┬────────┘    └──────────────────────┘
             │
             ▼
    ┌──────────────────────────────────────┐
    │  Slash Command Job (Sidekiq)         │
    │  - Query Backlog API (GitHub/Nulab)  │
    │  - Apply filters (sprint, status)    │
    │  - Format data for AI analysis       │
    └────────┬────────────────────────────┘
             │
             ▼
    ┌──────────────────────────────────────┐
    │  Data Processing Pipeline            │
    │  - Extract issues from backlog       │
    │  - Normalize fields & metadata       │
    │  - Build context for AI prompt       │
    └────────┬────────────────────────────┘
             │
             ▼
    ┌──────────────────────────────────────┐
    │  AI Analysis (Gemini)                │
    │  - Input: Backlog data + prompt      │
    │  - Output: Structured analysis       │
    │  - Generate report summary           │
    │  - Format recommendations            │
    └────────┬────────────────────────────┘
             │
             ▼
    ┌──────────────────────────────────────┐
    │  Slack Response Formatter            │
    │  - Build rich message blocks         │
    │  - Add tables, charts, metrics       │
    │  - Include action buttons (optional) │
    │  - Post to channel / thread          │
    └────────┬────────────────────────────┘
             │
             ▼
    ┌──────────────────────────────────────┐
    │  Slack API Post Response             │
    │  - chat.postMessage() to channel     │
    │  - Response appears in Slack         │
    └──────────────────────────────────────┘
```

### **Flow Chi Tiết:**

1. **User Issues Slash Command** → `/sprint-report sprint-1 --project=PROJ`
2. **Slack Sends** → HTTP POST to `/api/v1/slack/slash-command` (public endpoint, no auth)
3. **System Receives & Routes** → Identifies command type & extracts parameters
4. **Fetch Backlog Data** → Call GitHub/Nulab adapter with filters (sprint, project, status)
5. **Data Formatting** → Normalize issue data, extract key metrics
6. **AI Processing** → Send formatted data + custom prompt to Gemini
7. **Generate Report** → AI returns analysis, summary, insights
8. **Format for Slack** → Build block kit message with tables, emojis, metrics
9. **Post to Slack** → Use Slack API to send rich message back to channel

---