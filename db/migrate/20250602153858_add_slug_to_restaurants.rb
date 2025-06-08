class AddSlugToRestaurants < ActiveRecord::Migration[7.1]
  def change
    add_column :restaurants, :slug, :string
    
    # 為現有餐廳生成 slug
    reversible do |dir|
      dir.up do
        Restaurant.reset_column_information
        Restaurant.find_each do |restaurant|
          slug = restaurant.name.parameterize
          # 如果中文名稱產生空 slug，使用 id 作為 fallback
          slug = "restaurant-#{restaurant.id}" if slug.blank?
          restaurant.update_column(:slug, slug)
        end
        
        # 填入資料後設定 not null 和索引
        change_column_null :restaurants, :slug, false
        add_index :restaurants, :slug, unique: true
      end
      
      dir.down do
        remove_index :restaurants, :slug
      end
    end
  end
end
