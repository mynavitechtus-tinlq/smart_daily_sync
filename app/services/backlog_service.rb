require 'net/http'
require 'json'

class BacklogService
  BASE_URL = ENV.fetch('BACKLOG_BASE_URL')
  API_KEY  = ENV.fetch('BACKLOG_API_KEY')

  def self.get_user_tasks(user_id:, project_ids: [], from: Date.yesterday, to: Date.today, count: 100, offset: 0)
    uri = URI("#{BASE_URL}/api/v2/issues")

    query_pairs = []
    query_pairs << ["apiKey", API_KEY]
    Array(project_ids).each { |p| query_pairs << ["projectId[]", p] } if project_ids.any?
    Array(user_id).each { |a| query_pairs << ["assigneeId[]", a] }

    query_pairs << ["updatedSince", from.strftime('%Y-%m-%d')]
    query_pairs << ["updatedUntil", to.strftime('%Y-%m-%d')]
    query_pairs << ["count", count]
    query_pairs << ["offset", offset] if offset.to_i > 0

    uri.query = URI.encode_www_form(query_pairs)

    res = Net::HTTP.get_response(uri)

    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("[BacklogService] Request failed: #{uri} => #{res.code} #{res.message}")
      Rails.logger.warn("[BacklogService] Body: #{res.body}")
      return []
    end

    tasks = JSON.parse(res.body)

    tasks.map do |t|
      {
        id: t["issueKey"],
        summary: t["summary"],
        status: t.dig("status", "name"),
        due_date: t["dueDate"],
        overdue: t["dueDate"].present? && Date.parse(t["dueDate"]) < Date.today,
        completed: t.dig("status", "name") == "Done"
      }
    end
  end
end
