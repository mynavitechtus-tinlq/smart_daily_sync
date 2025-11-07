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
end
