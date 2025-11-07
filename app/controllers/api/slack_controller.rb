class Api::SlackController < ApplicationController
  skip_before_action :verify_authenticity_token

  # Slack slash command: /daily
  def commands
     Rails.logger.info "[Slack] Params: #{params.inspect}"
    
    if params[:command] == '/daily'
      slack_user_id = params[:user_id]
      slack_channel_id = params[:channel_id]
      trigger_id = params[:trigger_id]
      errors = []

      slack_user = SlackUser.find_by(slack_user_id: slack_user_id)
      errors << "Slack user #{params[:user_name]} not found" if slack_user.blank?
      slack_channel = SlackChannel.find_by(slack_channel_id: slack_channel_id)
      errors << "Slack channel #{params[:channel_name]} not found" if slack_channel.blank?

      return render json: { errors: errors.join(", ") }, status: :not_found if errors.present?

      report = ReportService.generate_for_user(slack_user, slack_channel)
      data = SlackService.open_modal(trigger_id:, slack_channel_id:, report:)

      render json: { ok: true }
    else
      render json: { text: "Unknown command" }
    end
  end

  # Submitting the form in slack, it will call this api.
  def interactions
    Rails.logger.info "[Slack] Params: #{params.inspect}"
    payload = JSON.parse(params[:payload])
    user_id = payload.dig('user', 'id')
    channel_id = payload['view']['private_metadata']
    view_state = payload.dig('view', 'state', 'values')
    yesterday_content = nil
    today_content = nil
    issues_content = nil

    view_state.values.each do |content|
      case content.keys
      when ['yesterday_input']
        yesterday_content = content['yesterday_input']['value']
      when ['today_input']
        today_content = content['today_input']['value']
      when ['issues_input']
        issues_content = content['issues_input']['value']
      end
    end

    Report.create!(
      slack_user_id: user_id,
      slack_channel_id: channel_id,
      yesterday_content: yesterday_content,
      today_content: today_content,
      issues_content: issues_content,
      date: Date.today
    )

    slack_user = SlackUser.find_by(slack_user_id: user_id)

    message_text = <<~TEXT
      *Report from:* #{slack_user.backlog_user_name}

      *Yesterday you did:* 
      #{yesterday_content}

      *Today you will do:* 
      #{today_content}

      *Issues:* 
      #{issues_content}
    TEXT

    # Then save the content after editing and send it to slack
    SlackService.send_message(channel_id, message_text)

    render json: { response_action: "clear" }
  end
end
