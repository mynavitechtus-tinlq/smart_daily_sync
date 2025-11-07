class CreateDailyReports < ActiveRecord::Migration[6.1]
  def change
    create_table :daily_reports do |t|
      t.string :user_id
      t.text :content
      t.datetime :reported_at
      t.boolean :auto_sent, default: false

      t.timestamps
    end
  end
end
