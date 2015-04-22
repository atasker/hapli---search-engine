class CreateCrawlers < ActiveRecord::Migration
  def change
    create_table :crawlers do |t|

      t.timestamps null: false
    end
  end
end
