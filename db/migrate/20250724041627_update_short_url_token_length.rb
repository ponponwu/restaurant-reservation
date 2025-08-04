class UpdateShortUrlTokenLength < ActiveRecord::Migration[8.0]
  def change
    # 更新 token 欄位長度從 6 字符增加到 8 字符
    change_column :short_urls, :token, :string, limit: 8, null: false
  end
end
