class CreateSlackChannels < ActiveRecord::Migration[6.1]
  def change
    create_table :slack_channels do |t|
      t.string :slack_channel_id
      t.string :slack_channel_name
      t.integer :backlog_project_id
      t.string :backlog_project_name

      t.timestamps
    end
  end
end
