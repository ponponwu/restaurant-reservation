class CreateShortUrls < ActiveRecord::Migration[8.0]
  def change
    create_table :short_urls do |t|
      t.string :token, null: false, limit: 6
      t.text :original_url, null: false
      t.datetime :expires_at, null: false
      t.integer :click_count, default: 0, null: false
      t.datetime :last_accessed_at
      t.timestamps
    end

    add_index :short_urls, :token, unique: true
    add_index :short_urls, :expires_at
    add_index :short_urls, :original_url
  end
end
