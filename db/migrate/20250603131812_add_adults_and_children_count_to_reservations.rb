class AddAdultsAndChildrenCountToReservations < ActiveRecord::Migration[7.1]
  def change
    add_column :reservations, :adults_count, :integer, null: false, default: 1
    add_column :reservations, :children_count, :integer, null: false, default: 0
    
    # 為現有資料設定預設值
    reversible do |dir|
      dir.up do
        # 將現有的 party_size 設為 adults_count，children_count 為 0
        execute "UPDATE reservations SET adults_count = party_size, children_count = 0 WHERE adults_count IS NULL"
      end
    end
  end
end
