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
	puts "post done"
  end

  def self.get_messages(
	channel:,
	oldest: Date.current.beginning_of_day.to_time.to_i,
	latest: Date.current.end_of_day.to_time.to_i
)
	slack_channel_id = channel.slack_channel_id
    uri = URI("#{SLACK_API_URL}/conversations.history?channel=#{slack_channel_id}&oldest=#{oldest}&latest=#{latest}")

    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{TOKEN}"
    req["Content-Type"] = "application/json"

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    res = http.request(req)
    data = JSON.parse(res.body)

	messages = (data["messages"] || []).reject do |msg|
      msg["subtype"] == "bot_message" || msg["bot_id"].present?
    end


	messages_with_replies = messages.map do |msg|
		if msg["reply_count"].to_i > 0
			thread_ts = msg["thread_ts"] || msg["ts"]

			replies_uri = URI("#{SLACK_API_URL}/conversations.replies?channel=#{slack_channel_id}&ts=#{thread_ts}")


			req_child = Net::HTTP::Post.new(replies_uri)
			req_child["Authorization"] = "Bearer #{TOKEN}"
			req_child["Content-Type"] = "application/json"

			http_child = Net::HTTP.new(replies_uri.host, replies_uri.port)
			http_child.use_ssl = true

			res_child = http_child.request(req_child)
			data_child = JSON.parse(res_child.body)

			messages_child = (data_child["messages"] || []).reject do |msg|
				msg["subtype"] == "bot_message" || msg["bot_id"].present?
			end

			msg["replies"] = messages_child
		end
		msg
	end
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
