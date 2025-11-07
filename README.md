# README

This README would normally document whatever steps are necessary to get the
application up and running.

# Slack Setup
Create a Slack App in your workspace: https://api.slack.com/apps

Add Bot Token Scopes: chat:write, im.write, ...

Install the app to your workspace

Copy SLACK_BOT_TOKEN and SLACK_CHANNEL_ID into .env

# Backlog Setup
Create a project in your backlog management tool (e.g., Jira, Notion)

Configure API token or integration key

Copy BACKLOG_API_KEY and BACKLOG_PROJECT_ID into .env

# Database Setup
Create Database

```
rails db:create
```

Initialize Database

```
rails db:migrate
```

Data example

Need to create data link between slack and backlog db/seeds.rb

# Start server
rails s

# Test locally (ngrok)
1. Install ngrok

```
brew install ngrok/ngrok/ngrok
```

2. Register an account (free)
Go to https://dashboard.ngrok.com/signup Sign up for free (just email or GitHub).

After logging in, you will sereade the Authtoken in the dashboard.

3. Connect ngrok to account

```
ngrok config add-authtoken <YOUR_AUTHTOKEN>
```

4. Open tunnel for Rails local

```
ngrok http 3000
```

# Note
In the future, we can develop some more features such as batch automatically sending reports if members have not reported

Statistics of tasks in a sprint

Show more details about stories, sub-tasks

...
