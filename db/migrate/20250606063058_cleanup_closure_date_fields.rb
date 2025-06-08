class CleanupClosureDateFields < ActiveRecord::Migration[7.1]
  def up
    # First, migrate any existing data that uses recurring_pattern to weekday
    migrate_recurring_pattern_data
    
    # Remove the recurring_pattern column since we're now using weekday
    remove_column :closure_dates, :recurring_pattern, :json
  end

  def down
    # Add back the recurring_pattern column
    add_column :closure_dates, :recurring_pattern, :json
    
    # Migrate weekday data back to recurring_pattern format
    migrate_weekday_to_pattern_data
  end

  private

  def migrate_recurring_pattern_data
    # Find all recurring closures that have recurring_pattern but no weekday
    ClosureDate.where(recurring: true).where(weekday: nil).find_each do |closure|
      next unless closure.recurring_pattern.present?
      
      begin
        pattern = JSON.parse(closure.recurring_pattern)
        if pattern['type'] == 'weekly' && pattern['weekday']
          weekday = pattern['weekday']
          if weekday.between?(1, 7)
            closure.update_column(:weekday, weekday)
            puts "Migrated closure ID #{closure.id}: weekday #{weekday}"
          end
        end
      rescue JSON::ParserError => e
        puts "Warning: Could not parse recurring_pattern for closure ID #{closure.id}: #{e.message}"
      end
    end
  end

  def migrate_weekday_to_pattern_data
    # Migrate weekday data back to recurring_pattern for rollback
    ClosureDate.where(recurring: true).where.not(weekday: nil).find_each do |closure|
      pattern = {
        'type' => 'weekly',
        'weekday' => closure.weekday
      }
      closure.update_column(:recurring_pattern, pattern.to_json)
      puts "Rollback: Migrated closure ID #{closure.id} back to pattern format"
    end
  end
end
