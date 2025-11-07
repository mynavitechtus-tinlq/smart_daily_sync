require 'net/http'
require 'json'

class SlackService
  SLACK_API_URL = 'https://slack.com/api'
  TOKEN = ENV.fetch('SLACK_BOT_TOKEN')

  # Open report import modal
  def self.open_modal(trigger_id:, slack_channel_id:, report:)
    uri = URI("#{SLACK_API_URL}/views.open")

		body = {
			trigger_id: trigger_id,
			view: {
				type: "modal",
				title: { type: "plain_text", text: "Daily Report" },
				private_metadata: slack_channel_id,
				blocks: [
					{
						type: "input",
						block_id: "yesterday_block",
						label: { type: "plain_text", text: "Yesterday you did" },
						element: {
							type: "plain_text_input",
							action_id: "yesterday_input",
							multiline: true,
							initial_value: report.yesterday_content || "N/A"
						}
					},
					{
						type: "input",
						block_id: "today_block",
						label: { type: "plain_text", text: "Today you will do" },
						element: {
							type: "plain_text_input",
							action_id: "today_input",
							multiline: true,
							initial_value: report.today_content || "N/A"
						}
					},
					{
						type: "input",
						block_id: "issues_block",
						label: { type: "plain_text", text: "Issues" },
						element: {
							type: "plain_text_input",
							action_id: "issues_input",
							multiline: true,
							initial_value: "N/A"
						}
					}
				],
				submit: { type: "plain_text", text: "Send" }
			}
		}

    post(uri, body)
  end

  # Send direct messages to the channel
  def self.send_message(channel_id, text)
    uri = URI("#{SLACK_API_URL}/chat.postMessage")
    body = {
      channel: channel_id,
      text: text
    }
    post(uri, body)
  end

  private

  def self.post(uri, body)
    Net::HTTP.post(
      uri,
      body.to_json,
      { "Content-Type" => "application/json", "Authorization" => "Bearer #{TOKEN}" }
    )
  end
end
