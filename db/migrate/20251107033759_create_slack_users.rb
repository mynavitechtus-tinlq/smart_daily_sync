class CreateSlackUsers < ActiveRecord::Migration[6.1]
  def change
    create_table :slack_users do |t|
      t.string :slack_user_id
      t.string :slack_user_name
      t.integer :backlog_user_id
      t.string :backlog_user_name
      t.string :backlog_user_email

      t.timestamps
    end
  end
end
