class ReportService
  def self.generate_for_user(slack_user, slack_channel)
    backlog_user_id = slack_user.backlog_user_id
    backlog_project_id = slack_channel.backlog_project_id
    # Lấy task hôm qua
    tasks_yesterday = BacklogService.get_user_tasks(
      user_id: backlog_user_id,
      from: Date.yesterday,
      to: Date.yesterday
    )

    # Lấy task hôm nay
    tasks_today = BacklogService.get_user_tasks(
      user_id: backlog_user_id,
      from: Date.today,
      to: Date.today
    )

    Report.new(
      slack_user_id: slack_user.slack_user_id,
      slack_channel_id: slack_channel.slack_channel_id,
      yesterday_content: format_tasks(tasks_yesterday),
      today_content: format_tasks(tasks_today),
      date: Date.today
    )
  end

  def self.generate_sprint_report(slack_channel)

    backlog_project_id = slack_channel.backlog_project_id

    # Lấy tất cả các thành viên trong project
    # Giả sử chúng ta có một phương thức để lấy tất cả user_id trong project
    sprint = BacklogService.get_sprint(project_id: backlog_project_id)

    if sprint.blank?
      Rails.logger.warn("⚠️ Không tìm thấy sprint hiện tại!")
      # Có thể gửi message báo lỗi lên Slack
      SlackService.send_message(slack_channel, "⚠️ Không tìm thấy sprint hiện tại.")
      return
    end

    tasks = BacklogService.get_tasks(project_id: backlog_project_id, sprint: sprint)

    if tasks.blank?
      Rails.logger.warn("⚠️ Không tìm thấy tasks của sprint hiện tại!")
      # Có thể gửi message báo lỗi lên Slack
      SlackService.send_message(slack_channel, "⚠️ Không tìm thấy tasks của sprint hiện tại.")
      return
    end

    content = generate_sprint_ai_prompt(sprint, tasks)

    puts content

    data = GeminiService.new(text: content).call

    puts "AI Response:"
    puts data

    if data['error'].present?
      message = "⚠️ Gemini API Error: #{data['error']['message']}"
      Rails.logger.warn(message)
      SlackService.send_message(slack_channel.slack_channel_id, message)
      return
    end

    texts = data["candidates"].map do |candidate|
      candidate.dig("content", "parts", 0, "text")
    end

    first_text = "*Sprint report*\n\n#{texts.first}"

    SlackService.send_message(slack_channel.slack_channel_id, first_text)
  end

  def self.generate_communication_report(slack_channel)
    messages = SlackService.get_messages(channel: slack_channel)

    puts "======"
    puts messages
    puts "======"

    messages_slack = messages.map do |msg|
      format_slack_message(msg)
    end


    content = generate_communication_ai_prompt(messages_slack)

    puts content

    data = GeminiService.new(text: content).call

    puts "AI Response:"
    puts data

    if data['error'].present?
      message = "⚠️ Gemini API Error: #{data['error']['message']}"
      Rails.logger.warn(message)
      SlackService.send_message(slack_channel.slack_channel_id, message)
      return
    end

    texts = data["candidates"].map do |candidate|
      candidate.dig("content", "parts", 0, "text")
    end
    first_text = "*Communication report*\n\n#{texts.first}"

    SlackService.send_message(slack_channel.slack_channel_id, first_text)
  end

  def self.format_slack_message(msg)
    formatted = []

    # 1. Main message
    main_text = clean_slack_text(msg["text"])
    formatted << "[Main] #{main_text}"

    # 2. Replies
    if msg["replies"]
      msg["replies"].each do |reply|
        reply_text = clean_slack_text(reply["text"])
        user = reply["user"]
        formatted << "[Reply by #{user}] #{reply_text}"
      end
    end

    formatted.join("\n")
  end

  # Hàm làm sạch text Slack (<@USER>, <https://link|TEXT>)
  def self.clean_slack_text(text)
    return "" unless text

    # remove slack link format <https://url|text> → text
    text = text.gsub(/<([^>|]+)\|([^>]+)>/, '\2')

    # remove <@U12345> → @U12345
    text = text.gsub(/<@([A-Z0-9]+)>/, '@\1')

    text
  end

  def self.format_message_slack(messages)
    root_ts = find_root_ts(messages)

    {
      thread_id: root_ts,
      messages: messages.map do |msg|
        {
          type: msg["ts"] == root_ts ? "root" : "reply",
          ts: msg["ts"],
          user: msg["user"],
          text: extract_text(msg)
        }
      end
    }
  end

  def self.find_root_ts(messages)
    root = messages.find { |msg| msg["thread_ts"].blank? }
    root ? root["ts"] : messages.first["thread_ts"]
  end

  # Text có thể nằm trong "text" hoặc trong "blocks"
  def self.extract_text(msg)
    return msg["text"] if msg["text"].present?
    return nil if msg["blocks"].blank?

    block_text = msg["blocks"].map do |b|
      next unless b["elements"]

      b["elements"].map do |el|
        if el["type"] == "rich_text_section"
          el["elements"].map { |t| t["text"] }.join(" ")
        end
      end
    end

    block_text.flatten.compact.join(" ")
  end

  def self.format_tasks(tasks)
    return "- No tasks recorded" if tasks.blank?

    tasks.map do |task|
      status = case task[:status]
              when "Done" then "✅ Completed"
              when "In Progress" then "🔄 In Progress"
              when "Open" then "📝 New"
              else "⚪ #{task[:status]}"
              end

      overdue_text =
        if task[:due_date].present? && task[:overdue]
          "⏰ Overdue (#{task[:due_date]})"
        elsif task[:due_date].present?
          "📅 Due: #{task[:due_date]}"
        else
          "📅 No due date"
        end

      "- [#{task[:id]}] #{task[:summary]} (#{status}, #{overdue_text})"
    end.join("\n")
  end

  def self.generate_sprint_ai_prompt(sprint, tasks)
    slack_user_map = SlackUser.all.pluck(:slack_user_id, :slack_user_name).to_h

    task_strings = tasks.map do |t|
      assignee = t['assignee'] ? t['assignee']['name'] : "Unassigned"
      due_date = t['dueDate'] || "No due date"
      status =  t['status'] ? t['status']['name'] : "Unknown"

      "- #{t['issueKey']}: #{t['summary']} | Assignee: #{assignee} | Status: #{status} | DueDate: #{due_date} | parentIssueId: #{t['parentIssueId'] || 'N/A'}, id: #{t['id']}"
    end.join("\n")

    prompt = <<~PROMPT
      Bạn là một Project Manager AI. Dưới đây là dữ liệu sprint hiện tại:

      Sprint: #{sprint['name']}
      Start date: #{sprint['startDate']}
      End date: #{sprint['releaseDueDate']}

      Task phân theo Milestone:

      #{task_strings}

      *Yêu cầu Định dạng Đầu ra (Output Format) cho Slack:*
      1. Sử dụng *Markdown dạng Slack* (chỉ dùng `*in đậm*`, `_nghiêng_`, `> quote`).
      2. Sử dụng Emoji để mô tả trạng thái:
          * 🔴 *Blocker/Critical/Quá hạn*
          * ⚠️ *Risk/Chậm tiến độ*
          * 🟢 *Hoàn thành*
      3. *Tất cả tiêu đề phải được in đậm bằng ký tự `*` thay vì `**`.*
      4. SLACK MENTION BẮT BUỘC:** Trong tất cả các mục (Assignee, Blocker, Hành Động Khẩn Cấp), hãy sử dụng cú pháp **`<@USER_ID>`** để tag đúng người dùng, sử dụng #{slack_user_map} thông tin để map tag slack*
      5. Hiện thị theo thông tin story và subtask của story đó dựa vào parentIssueId và key của task.
      6. [DD/MM/YYYY] Hiện thị ngày gửi

      *# DAILY PROJECT CHECK - [DD/MM/YYYY]*

      *## 1. PROGRESS BY FEATURE/ASSIGNEE*
      * *🔹 [Feature [issueKey]]*
        * *Assignee:* @User
        * *Vấn đề:* [Nội dung]
        * *Trang thái:*

        Hiển thị icon:
        🔹 Main Task
        🐞 Bug
        ⚙️ Task

      *## 2. HIGHLIGHTS & RISKS*
      * 🔴 *Blocker/Quá Hạn:* [Nội dung]
      * ⚠️ *Risk/Cảnh Báo:* [Nội dung]

      Hãy phân tích, đánh giá, và tạo báo cáo theo format trên.
    PROMPT

    prompt
  end

  def self.generate_communication_ai_prompt(messages)
    slack_user_map = SlackUser.all.pluck(:slack_user_id, :slack_user_name).to_h

    prompt = <<~PROMPT
      Bạn là công cụ phân tích giao tiếp Slack của đội phát triển phần mềm.

      Tôi sẽ gửi vào trường `messages` toàn bộ tin nhắn Slack trong 1 ngày.

      Hãy phân tích và trả về một đoạn nội dung ngắn gọn, đủ ý, rõ ràng, tóm tắt để tôi gửi thẳng lên Slack. 
      ⚠️ Chỉ trả về NỘI DUNG THUẦN VĂN BẢN, không dùng JSON.

      SLACK MENTION BẮT BUỘC:** Trong tất cả các mục (Assignee, Blocker, Hành Động Khẩn Cấp), hãy sử dụng cú pháp **`<@USER_ID>`** để tag đúng người dùng, sử dụng #{slack_user_map} thông tin để map tag slack*

      Format nội dung trả về:

      - Ticket/Backlog liên quan: ...
      - Các vấn đề phát hiện: 
        + ...
        + ...
      - Gợi ý cải thiện:
        ...

      Dữ liệu Slack cần phân tích:
      #{messages.to_json}
    PROMPT
  end
end
