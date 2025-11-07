require "test_helper"

class Api::SlackControllerTest < ActionDispatch::IntegrationTest
  test "should get commands" do
    get api_slack_commands_url
    assert_response :success
  end

  test "should get interactions" do
    get api_slack_interactions_url
    assert_response :success
  end

  test "should get reports" do
    get api_slack_reports_url
    assert_response :success
  end
end
