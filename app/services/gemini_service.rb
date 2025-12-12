class GeminiService
  GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
  # GEMINI_URL= "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-preview:generateContent"

  def initialize(text:)
    @text = text
    @api_key = ENV['GEMINI_KEY']
  end

  def call
    uri = URI(GEMINI_URL)

    req = Net::HTTP::Post.new(uri)
    req["x-goog-api-key"] = @api_key
    req["Content-Type"] = "application/json"

    req.body = {
      contents: [
        {
          parts: [
            { text: @text }
          ]
        }
      ]
    }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    JSON.parse(res.body) rescue res.body
  end
end
