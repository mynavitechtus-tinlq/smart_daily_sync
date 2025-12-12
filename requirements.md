# Yêu cầu dự án: Phân tích chat Slack và kiểm tra backlog

## Mục tiêu
- Tự động lắng nghe các tin nhắn trong Slack khi mọi người chat.
- Lấy thông tin liên quan từ hệ thống backlog (ví dụ: Jira, GitHub Issues, Trello).
- Gửi dữ liệu thu thập được tới một dịch vụ AI để phân tích: phát hiện vấn đề trong thông tin Slack (vấn đề làm rõ, xung đột, rủi ro, cảm xúc tiêu cực, requests chưa rõ ràng) và kiểm tra xem backlog đã được phân hoạch vào planning/assign task hợp lý chưa.
- Cung cấp cảnh báo, gợi ý hành động, hoặc tự động đề xuất cập nhật backlog/assign task.

## Các bên liên quan
- Product Manager / Team Lead: nhận cảnh báo, insight để điều chỉnh planning.
- Developer / Assignee: nhận task được đề xuất hoặc thay đổi assign.
- Scrum Master / PMO: theo dõi trạng thái planning và rủi ro.
- Người dùng Slack: nguồn dữ liệu (tin nhắn, kênh, thread).

## Phạm vi (Scope)
- Bao gồm: lắng nghe và thu thập message từ các kênh Slack được cấu hình; mapping message với backlog item; gửi dữ liệu tới AI để phân tích; báo cáo kết quả và (tùy cấu hình) tạo/update/assign task trên hệ thống backlog.
- Không bao gồm: thay đổi tự động phạm vi planning lớn (chỉ đề xuất hoặc hành động khi có xác nhận) — có thể cấu hình sau.

## Use cases chính
1. Phát hiện issue mới trong Slack: AI phân tích message thấy một yêu cầu/bug chưa có trên backlog -> đề xuất tạo issue với tiêu đề, mô tả, priority.
2. Phát hiện task bị assign sai: AI so sánh nội dung thread với owner và gợi ý reassign.
3. Kiểm tra placement vào planning: AI phân tích backlog item và so sánh với sprint/planning để đánh giá xem item có phù hợp với sprint hiện tại không.
4. Phát hiện rủi ro/émotion: cảnh báo nếu nhiều tin nhắn tiêu cực hoặc escalations xuất hiện.
5. Audit và report hàng tuần: tóm tắt các vấn đề phát hiện, số lượng đề xuất thực hiện, tỷ lệ chấp nhận đề xuất.

## Yêu cầu chức năng (Functional Requirements)
1. Slack Listener
   - Hỗ trợ Slack Events API và/hoặc RTM API.
   - Lắng nghe các event: message.channels, message.groups, message.im, message.mpim, thread replies.
   - Lọc kênh/thuộc tính theo cấu hình (ví dụ: chỉ kênh #engineering, #product).
2. Backlog Connector
    - Hỗ trợ kết nối tới các hệ thống backlog: Nulab Backlog (Backlog API) và GitHub (Issues/Repos). Cần có connector riêng cho mỗi hệ thống.
    - Các khả năng chung:
       - Truy vấn bằng từ khoá, label, assignee, status, hoặc mapping với thread (ví dụ: chứa `PROJECT-123` hoặc `#issue-number`).
       - Tìm kiếm bằng similarity (so sánh text message với title/description của issue) nếu không có reference rõ ràng.
       - Tạo, cập nhật, assign issue khi được approved.

    - Nulab Backlog (Backlog API) — notes:
       - Authentication: API Key (Project-level) hoặc personal API key; dùng header `X-Api-Key` hoặc query param `apiKey` theo tài liệu Backlog.
       - Endpoints chính:
          - GET /projects/{projectIdOrKey}/issues — danh sách issue theo filter.
          - GET /issues/{issueId} — lấy chi tiết issue.
          - POST /issues — tạo issue mới.
          - PATCH /issues/{issueId} — cập nhật issue (assignee, status, custom fields).
       - Rate limits và retry: tuân theo giới hạn của Backlog; dùng exponential backoff khi 429.
       - Mapping fields (gợi ý):
          - backlog.id -> id
          - backlog.issueKey -> key
          - summary -> title
          - description -> description
          - assignee -> assignee (loginId or id)
          - priority/status/estimatedHours -> labels/fields

    - GitHub Issues (REST API) — notes:
       - Authentication: Personal Access Token (PAT) hoặc GitHub App token; truyền qua header `Authorization: token <TOKEN>`.
       - Endpoints chính:
          - GET /repos/{owner}/{repo}/issues — truy vấn issue/PR theo filter (state, labels, assignee).
          - GET /repos/{owner}/{repo}/issues/{issue_number} — chi tiết.
          - POST /repos/{owner}/{repo}/issues — tạo issue.
          - PATCH /repos/{owner}/{repo}/issues/{issue_number} — cập nhật.
       - Rate limits: theo GitHub API; hỗ trợ conditional requests (ETag) và backoff trên 403/429.
       - Mapping fields (gợi ý):
          - id/number -> id/number
          - title -> title
          - body -> description
          - assignee(s) -> assignees
          - labels -> labels

    - Connector behavior & design notes:
       - Connector sẽ expose interface chung trong backend: findIssues(query), getIssue(id), createIssue(payload), updateIssue(id,payload).
       - Adapter pattern: mỗi hệ thống (Backlog, GitHub) implement adapter để chuyển payload chung sang định dạng provider.
       - Khi mapping từ Slack message -> backlog item: tìm reference trực tiếp (issue key/number) trước; nếu không có, thực hiện similarity search và trả confidence score.
       - Lưu metadata: source_system, source_id, fetched_at để audit.
3. Extractor & Normalizer
   - Trích xuất thông tin quan trọng từ message (ý định, từ khoá, người liên quan, deadline nói trong message).
   - Chuẩn hoá định dạng thời gian, user mentions, links.
4. AI Analysis
   - Gửi payload tóm tắt (context từ Slack + thông tin backlog liên quan) tới mô hình AI.
   - Mô tả các loại phân tích: intent detection (request, bug, question), sentiment analysis, relevance to backlog item, suggestion (create/update/assign), confidence score.
   - Truy xuất và lưu response để audit.
5. Action Engine
   - Cung cấp khả năng: a) thông báo (post message vào Slack), b) tạo/update issue trên backlog, c) gửi email hoặc webhooks.
   - Hành động chỉ tự động khi cấu hình allow_auto_action=true; mặc định là tạo đề xuất và gửi cho reviewer.
6. UI/Reporting ( tối thiểu )
   - Dashboard (web) hoặc chỉ báo cáo định kỳ: danh sách đề xuất, trạng thái (pending/accepted/rejected), số liệu tóm tắt.

7. Public API (no auth)
   - Mô tả: Các endpoint API công khai của dịch vụ (ví dụ: `/api/v1/backlog`, `/api/v1/ai/analyze`) sẽ không yêu cầu authentication — tức là public endpoints.
   - Lý do: theo yêu cầu, hệ thống cần cung cấp API công khai để dễ dàng tích hợp hoặc demo mà không cần cung cấp token.
   - Hành vi & giới hạn:
     - Các endpoint public chỉ cung cấp các hành động đọc và tạo đề xuất (suggestions). Hành động thay đổi trực tiếp trên hệ thống backlog (create/update/assign) mặc định sẽ yêu cầu allow_auto_action=true trong cấu hình hệ thống — mặc định là false.
     - Vì không có auth, hệ thống phải áp dụng các biện pháp giảm thiểu rủi ro khác (xem phần Bảo mật bên dưới): rate limiting, throttling, request size limits, và ops alerting.
     - Có thể cung cấp optional API key hoặc IP allowlist cho các môi trường production nếu muốn nâng mức bảo mật sau này.

## Yêu cầu phi chức năng (Non-functional)
- Độ trễ: phân tích cho message quan trọng cần phản hồi trong vòng 1-2 phút (tùy cấu hình); report batch hàng ngày hoặc weekly.
- Khả năng mở rộng: xử lý đồng thời nhiều event; queue-based processing (RabbitMQ/Redis/Sidekiq).
- Độ chính xác: AI phải trả về confidence score; hệ thống phải cung cấp cách huấn luyện/tinh chỉnh mô hình nếu nhiều false-positive.
- Logging & tracing: lưu toàn bộ payload input/output cho audit; hỗ trợ tracing request-id.
- Observability: health checks, metrics (requests/sec, queue length, success/failure rates).

## Dữ liệu & Schema
- Slack message payload (thu gọn): { message_id, channel_id, user_id, text, thread_ts, ts, attachments }
- Backlog item payload (thu gọn): { id, system, key, title, description, assignee, status, labels, sprint }
- AI request payload: { context_text, recent_messages[], related_backlog_items[], metadata: { channel, thread, timestamp } }
- AI response (expected): { issues_detected[], suggestions[], sentiment_score, confidence }

## Tích hợp AI
  - tóm tắt cuộc trao đổi,
  - phát hiện intent & sentiment,
  - so sánh với backlog item và đưa ra đề xuất (create/update/assign) kèm lý do, bước thực hiện và confidence.

### Gemini (Google Vertex AI) integration — notes

- Overview:
   - Gemini family models (via Google Vertex AI / Gen AI) có thể dùng để thực hiện phân tích ngôn ngữ (intent detection, summarization, sentiment, structured suggestions) tương tự OpenAI-style models.
   - Cần quyết định model cụ thể (ví dụ: Gemini Pro/Ultra/1.5 tuỳ khả năng/chi phí/latency).

- Authentication & permissions:
   - Không yêu cầu authentication cho các endpoint public (no-auth) theo yêu cầu; các lời gọi tới Gemini qua service sẽ được coi là public.
   - Lưu ý: vì thiết lập no-auth cho các endpoint gửi prompt tới Gemini sẽ làm tăng rủi ro lạm dụng/cost — cân nhắc giới hạn rate và monitoring (xem phần Public API và Security).
   - Nếu sau này muốn bảo mật hơn, có thể thêm option sử dụng Service Account / Google credentials và chuyển sang authenticated calls.

- Client options / calling the API:
   - Option A (recommended): dùng Google Cloud client libs cho Ruby (ví dụ `google-cloud-aiplatform` nếu phù hợp) hoặc official REST API bằng HTTP client (Faraday/Net::HTTP) với OAuth2.
   - Option B: gọi Vertex AI REST endpoints trực tiếp bằng service account access token (obtain via google-auth library or gcloud), gửi prompt + context và nhận response.
   - Chọn location (region) hợp lý để giảm latency (ví dụ: `us-central1`, `asia-east1`) và dùng model name theo docs: `projects/{project}/locations/{location}/models/{model}`.

- Payload & structured output:
   - Gửi input tóm tắt (1) conversation context, (2) related backlog items, (3) task: phân loại intent/sentiment/relavance/suggestion.
   - Yêu cầu model trả về JSON có cấu trúc để dễ parse, ví dụ: { "intent": "bug|request|question", "sentiment": "positive|neutral|negative", "suggestions": [{"action":"create_issue","title":"...","body":"...","assignee":"...","confidence":0.92}], "related_issue_keys": ["PROJ-123"], "explanation":"..." }
   - Đặt prompt/template rõ ràng (system instruction + user content + strict JSON output instruction) và validate JSON trả về; fallback: nếu text không parse được, gọi model với prompt để chỉ trả JSON.

- Token limits, chunking & long contexts:
   - Gemini model có giới hạn context token; nếu cuộc trao đổi quá dài, áp dụng các chiến lược:
      - Truncate older messages bằng cách tóm tắt (summary) trước khi gửi.
      - Chunking: chia context thành các phần và gọi model nhiều lần, hoặc dùng retrieval + summarization.
   - Lưu ý cost khi gửi nhiều chunk.

- Latency & streaming:
   - Mong đợi latency vài trăm ms đến vài giây tuỳ model và region; ghi vào SLA/requirements.
   - Nếu cần feedback real-time (progressive suggestions), xem xét streaming endpoints (nếu provider hỗ trợ) hoặc dùng non-blocking UI với progress state.

- Error handling, rate limits & retries:
   - Thiết kế retry với exponential backoff cho transient errors (5xx, 429). Có giới hạn retry để tránh amplification.
   - Monitor quota/cost và bật alert khi vượt ngưỡng.

- Security & privacy with Gemini:
   - Không gửi PII hoặc secret tokens trong prompt; trước khi gửi, apply masking rules hoặc strip sensitive fields.
   - Nếu phải gửi thông tin nhạy cảm, kiểm tra Terms of Service của provider và có consent rõ ràng.
   - Lưu prompt/response cho auditing nhưng mask sensitive tokens.

- Cost & operational notes:
   - Đánh giá chi phí theo số token và số request; làm tests với representative traffic để ước lượng.
   - Cân nhắc caching responses cho cùng một context hoặc re-use summarized context để giảm cost.

- Implementation checklist (developer-facing):
   - [ ] Thêm config để bật/tắt Gemini provider và chọn model/region.
   - [ ] Implement provider adapter `AiProviders::GeminiAdapter` với methods: analyze(context), generate_suggestion(payload), summarize(messages).
   - [ ] Tích hợp retry, metrics (latency, success rate), and cost-metering (tokens/request).
   - [ ] Tạo prompt templates và unit tests to validate JSON-shaped responses.
   - [ ] Implement secrets handling via Rails credentials or env + document deploy steps.

   ## Sample API payloads (public endpoints)

   1) GET /api/v1/backlog?system=github&q=search-term

   Request: (no body)

   Response (200):
   {
      "issues": [
         { "id": 123, "key": "GH-123", "title": "Example issue", "assignee": "alice", "status": "open" }
      ],
      "source": "github",
      "query": "search-term"
   }

   2) POST /api/v1/backlog?system=nulab

   Request body (application/json):
   {
      "issue": {
         "title": "User reported bug: unable to save",
         "description": "Steps to reproduce...",
         "assignee": "bob",
         "labels": ["bug", "urgent"]
      }
   }

   Response (201):
   {
      "id": 456,
      "source": "nulab",
      "created": true,
      "payload": { "title": "User reported bug: unable to save", "assignee": "bob" }
   }

   3) POST /api/v1/ai/analyze

   Request body (application/json):
   {
      "context_text": "We keep seeing error X when saving user profile...",
      "recent_messages": ["..."],
      "related_backlog_items": []
   }

   Response (200):
   {
      "model": "gemini-stub",
      "intent": "bug",
      "sentiment": "neutral",
      "suggestions": [
         { "action": "create_issue", "title": "Investigate save error", "body": "...", "assignee": null, "confidence": 0.75 }
      ],
      "raw_payload": { /* echo of request */ }
   }


## Bảo mật & Quyền riêng tư
- Chỉ thu thập message từ channel được phép theo cấu hình.
- Mã hóa transit và rest cho dữ liệu nhạy cảm (TLS, DB encryption-at-rest nếu cần).
- Quyền truy cập: API keys cho Slack, backlog, AI phải lưu trong secret manager (Vault, environment variables, Rails credentials `config/credentials.yml.enc`).
 - Quyền truy cập & connectors:
    - Connectors tới hệ thống bên thứ ba (Slack, Nulab Backlog, GitHub, AI providers) vẫn yêu cầu credentials/API keys và phải lưu an toàn trong secret manager (Google Secret Manager, Vault, environment variables, hoặc Rails credentials `config/credentials.yml.enc`).
    - Tuy nhiên, các API công khai của dịch vụ (public endpoints) được triển khai theo yêu cầu không yêu cầu authentication. Vì vậy phải áp dụng các biện pháp giảm thiểu rủi ro (rate limiting, throttling, payload size limits, monitoring).
- Masking: khi lưu logs, mask PII (email, phone, token) theo pattern.
- Retention: chính sách giữ logs và messages (ví dụ: giữ 90 ngày cho logs, 1 năm cho audit theo yêu cầu pháp lý).

## Thông báo & UX
- Khi phát hiện đề xuất, bot sẽ post 1 message vào thread kèm nút actions (Approve / Reject / More info).
- Khi user approve, hệ thống sẽ thực hiện action (create/assign/update) nếu allow_auto_action=true.
- Mỗi đề xuất kèm: summary 1-2 câu, confidence, suggested action, liên kết tới backlog.

## Tiêu chí nghiệm thu (Acceptance Criteria)
- Hệ thống lắng nghe message và tạo bản ghi event trong DB cho mọi message tới các channel được cấu hình.
- AI có thể phân loại ít nhất 3 loại intent: request, bug report, question với confidence > threshold.
- Hệ thống có thể map message tới backlog item hiện có khi chứa reference key hoặc similarity score > threshold.
- Một workflow đề xuất tạo issue hoạt động: từ Slack -> generate suggestion -> user approve -> tạo issue trên Jira/GitHub.

## Kịch bản test mẫu
- Happy path: user báo bug trong một thread; hệ thống đề xuất tạo issue; reviewer approve; issue xuất hiện trong backlog với đúng metadata.
- Edge case: message chứa PII -> system masks thông tin trong logs; suggestion không lưu PII.
- False positive control: hệ thống đưa ra ít nhất 1 cách để user reject và ghi lý do (feedback) để cải thiện mô hình.

## Giả định
- Sử dụng Slack Events API và có quyền cài bot vào các channel cần theo dõi.
- Hệ thống backlog có API để tạo/update issues (Jira REST, GitHub token).
- Sử dụng một dịch vụ AI có thể xử lý prompt & trả về structured JSON.

## Rủi ro
- Sai khớp ngữ cảnh dẫn tới false-positive/negative -> cần loop feedback để tinh chỉnh.
- Vấn đề bảo mật/PII khi phân tích message -> cần masking/consent.
- Giới hạn API rate của Slack/Jira/AI -> cần backoff và queueing.

## Next steps
1. Review `requirements.md` với stakeholders và điều chỉnh thresholds & channels theo nhu cầu.
2. Thiết kế kiến trúc và mô tả API contract (payload schemas, endpoints).
3. Triển khai prototype minimal: Slack listener + simple AI call + create suggestion flow.
4. Thực hiện test privacy & load.

---

Tệp này được tạo tự động. Sau khi bạn review, tôi có thể giúp:
- tinh chỉnh nội dung bằng yêu cầu cụ thể hơn,
- tạo sơ đồ kiến trúc (diagram),
- scaffold prototype trong repo hiện tại (ví dụ: thêm job/worker, config Slack, connector Jira).