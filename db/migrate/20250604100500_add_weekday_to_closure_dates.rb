class AddWeekdayToClosureDates < ActiveRecord::Migration[6.1]
  def change
    add_column :closure_dates, :weekday, :integer, comment: '0-6 表示週日到週六'
    add_index :closure_dates, :weekday
    
    # 將現有的 recurring_pattern 資料遷移到 weekday
    reversible do |dir|
      dir.up do
        ClosureDate.reset_column_information
        ClosureDate.where(recurring: true).find_each do |closure|
          next if closure.recurring_pattern.blank?
          
          begin
            pattern = closure.recurring_pattern.is_a?(String) ? JSON.parse(closure.recurring_pattern) : closure.recurring_pattern
            if pattern.is_a?(Hash) && pattern['type'] == 'weekly' && pattern['weekday'].present?
              closure.update_column(:weekday, pattern['weekday'])
            end
          rescue JSON::ParserError, TypeError => e
            puts "Error migrating closure ##{closure.id}: #{e.message}"
            next
          end
        end
      end
    end
  end
end
