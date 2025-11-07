class CreateReports < ActiveRecord::Migration[6.1]
  def change
    create_table :reports do |t|
      t.string :slack_user_id
      t.string :slack_channel_id
      t.text :yesterday_content
      t.text :today_content
      t.text :issues_content
      t.date :date

      t.timestamps
    end
  end
end
