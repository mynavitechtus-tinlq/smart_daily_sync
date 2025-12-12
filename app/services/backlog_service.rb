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

  def self.get_sprint(project_id:, date: Date.current)
    uri = URI("#{BASE_URL}/api/v2/projects")

    # Nếu bạn muốn lấy nhiều project, gọi riêng từng project để lấy versions
    sprints = []

    sprint_uri = URI("#{BASE_URL}/api/v2/projects/#{project_id}/versions")
    query_pairs = [["apiKey", API_KEY]]
    sprint_uri.query = URI.encode_www_form(query_pairs)

    res = Net::HTTP.get_response(sprint_uri)

    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("[BacklogService] Request failed: #{sprint_uri} => #{res.code} #{res.message}")
      Rails.logger.warn("[BacklogService] Body: #{res.body}")
      return nil
    end

    sprints = JSON.parse(res.body)
    
    # Lọc sprint hiện tại
    return sprints.find do |sprint|
      start_date = sprint["startDate"] ? Date.parse(sprint["startDate"]) : nil
      end_date   = sprint["releaseDueDate"] ? Date.parse(sprint["releaseDueDate"]) : nil

      start_date && end_date && start_date <= date && date <= end_date
    end
  end

  # def self.get_tasks(project_id:, sprint:)
  #   uri = URI("#{BASE_URL}/api/v2/issues")

  #   # TODO check timezone date incorrect ?
  #   from = sprint["startDate"] ? Date.parse(sprint["startDate"]) : Date.current
  #   to = sprint["releaseDueDate"] ? Date.parse(sprint["releaseDueDate"]) : Date.current

  #   query_pairs = []
  #   query_pairs << ["apiKey", API_KEY]
  #   # query_pairs << ["projectId[]", project_id]
  #   # query_pairs << ["updatedSince", from.strftime('%Y-%m-%d')]
  #   # query_pairs << ["updatedUntil", to.strftime('%Y-%m-%d')]
  #   query_pairs << ["milestoneId[]", sprint["id"]]
  #   query_pairs << ["milestoneId[]", 150321]

  #   uri.query = URI.encode_www_form(query_pairs)

  #   res = Net::HTTP.get_response(uri)

  #   unless res.is_a?(Net::HTTPSuccess)
  #     Rails.logger.warn("[BacklogService] Request failed: #{uri} => #{res.code} #{res.message}")
  #     Rails.logger.warn("[BacklogService] Body: #{res.body}")
  #     return []
  #   end

  #   JSON.parse(res.body)
  # end

  def self.get_tasks(project_id:, sprint:)
    all_issues = []
    count = 100
    offset = 0

    loop do
      uri = URI("#{BASE_URL}/api/v2/issues")

      query_pairs = []
      query_pairs << ["apiKey", API_KEY]
      # nếu bạn muốn giới hạn theo project uncomment:
      # query_pairs << ["projectId[]", project_id]

      # milestone filters (giữ như bạn ghi)
      query_pairs << ["milestoneId[]", sprint["id"]]
      # query_pairs << ["milestoneId[]", 150321]

      # phân trang
      query_pairs << ["count", count]
      query_pairs << ["offset", offset]

      uri.query = URI.encode_www_form(query_pairs)

      res = Net::HTTP.get_response(uri)

      unless res.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[BacklogService] Request failed: #{uri} => #{res.code} #{res.message}")
        Rails.logger.warn("[BacklogService] Body: #{res.body}")
        break
      end

      batch = JSON.parse(res.body)
      # bảo đảm batch là mảng
      unless batch.is_a?(Array)
        Rails.logger.warn("[BacklogService] Unexpected response format for #{uri}: #{batch.class}")
        break
      end

      all_issues.concat(batch)

      # nếu ít hơn count thì đã hết
      break if batch.size < count

      offset += count
    end

    all_issues
  rescue JSON::ParserError => e
    Rails.logger.warn("[BacklogService] JSON parse error: #{e.message}")
    []
  end
end
