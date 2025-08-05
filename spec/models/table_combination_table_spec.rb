require 'rails_helper'

RSpec.describe TableCombinationTable, type: :model do
  let(:restaurant) { create_batch_safe(:restaurant) }
  let(:table_group) { create(:table_group, restaurant: restaurant) }
  let(:table1) { create(:table, restaurant: restaurant, table_group: table_group, can_combine: true, table_number: 'T1') }
  let(:table2) { create(:table, restaurant: restaurant, table_group: table_group, can_combine: true, table_number: 'T2') }
  let(:reservation) { create_batch_safe(:reservation, restaurant: restaurant) }
  let(:table_combination) { build(:table_combination, :without_tables, reservation: reservation) }

  describe 'associations' do
    it { is_expected.to belong_to(:table_combination) }
    it { is_expected.to belong_to(:restaurant_table) }
  end

  describe 'validations' do
    subject do
      # 為了測試唯一性驗證，我們需要一個已保存的 table_combination
      saved_combination = create_clean_table_combination(restaurant: restaurant, table_count: 2)
      build(:table_combination_table, table_combination: saved_combination, restaurant_table: table1) 
    end

    it { is_expected.to validate_uniqueness_of(:table_combination_id).scoped_to(:restaurant_table_id) }

    context 'table must be combinable' do
      let(:empty_combination) { build(:table_combination, :without_tables, reservation: reservation) }
      
      it 'is valid when table can_combine is true' do
        table1.update!(can_combine: true)
        combination_table = build(:table_combination_table, table_combination: empty_combination, restaurant_table: table1)
        expect(combination_table).to be_valid
      end

      it 'is invalid when table can_combine is false' do
        table1.update!(can_combine: false)
        combination_table = build(:table_combination_table, table_combination: empty_combination, restaurant_table: table1)
        expect(combination_table).not_to be_valid
        expect(combination_table.errors[:restaurant_table]).to include('該桌位不支援併桌')
      end
    end
  end

  describe 'factory' do
    it 'creates valid table combination table' do
      # 創建一個有桌位的 table_combination 來測試 factory
      table_combination_with_tables = create_clean_table_combination(restaurant: restaurant, table_count: 2)
      combination_table = table_combination_with_tables.table_combination_tables.first
      
      expect(combination_table).to be_valid
      expect(combination_table.restaurant_table.can_combine).to be true
    end
  end
end
