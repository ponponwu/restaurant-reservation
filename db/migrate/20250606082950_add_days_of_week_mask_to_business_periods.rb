class AddDaysOfWeekMaskToBusinessPeriods < ActiveRecord::Migration[7.1]
  # 星期對應的位元值
  DAYS_OF_WEEK_MAPPING = {
    'monday' => 1,      # 0000001
    'tuesday' => 2,     # 0000010  
    'wednesday' => 4,   # 0000100
    'thursday' => 8,    # 0001000
    'friday' => 16,     # 0010000
    'saturday' => 32,   # 0100000
    'sunday' => 64      # 1000000
  }.freeze

  def up
    # 1. 添加新的 bitmask 欄位
    add_column :business_periods, :days_of_week_mask, :integer, default: 0, null: false
    add_index :business_periods, :days_of_week_mask

    # 2. 遷移現有數據（使用原始 SQL 避免 ActiveRecord 模型問題）
    execute <<-SQL
      UPDATE business_periods 
      SET days_of_week_mask = (
        CASE 
          WHEN days_of_week::text LIKE '%monday%' THEN 1 ELSE 0 END +
          CASE 
            WHEN days_of_week::text LIKE '%tuesday%' THEN 2 ELSE 0 END +
          CASE 
            WHEN days_of_week::text LIKE '%wednesday%' THEN 4 ELSE 0 END +
          CASE 
            WHEN days_of_week::text LIKE '%thursday%' THEN 8 ELSE 0 END +
          CASE 
            WHEN days_of_week::text LIKE '%friday%' THEN 16 ELSE 0 END +
          CASE 
            WHEN days_of_week::text LIKE '%saturday%' THEN 32 ELSE 0 END +
          CASE 
            WHEN days_of_week::text LIKE '%sunday%' THEN 64 ELSE 0 END
      )
      WHERE days_of_week IS NOT NULL
    SQL
  end

  def down
    remove_index :business_periods, :days_of_week_mask if index_exists?(:business_periods, :days_of_week_mask)
    remove_column :business_periods, :days_of_week_mask
  end
end
