class TableCombinationTable < ApplicationRecord
  belongs_to :table_combination
  belongs_to :restaurant_table
  
  validates :table_combination_id, uniqueness: { scope: :restaurant_table_id }
  validate :table_must_be_combinable
  
  private
  
  def table_must_be_combinable
    return unless restaurant_table
    
    unless restaurant_table.can_combine?
      errors.add(:restaurant_table, '該桌位不支援併桌')
    end
  end
end
