require 'rails_helper'

RSpec.describe TableCombination do
  # 1. 關聯測試
  describe 'associations' do
    it { is_expected.to belong_to(:reservation) }
    it { is_expected.to have_many(:table_combination_tables).dependent(:destroy) }
    it { is_expected.to have_many(:restaurant_tables).through(:table_combination_tables) }
  end

  # 2. 驗證測試
  describe 'validations' do
    # 使用批次安全的創建方法
    let!(:restaurant) { create_batch_safe(:restaurant) }
    let!(:table_group) { create(:table_group, restaurant: restaurant) }
    let!(:table1) { create_batch_safe(:table, restaurant: restaurant, table_group: table_group, capacity: 4, can_combine: true) }
    let!(:table2) { create_batch_safe(:table, restaurant: restaurant, table_group: table_group, capacity: 4, can_combine: true) }
    let!(:reservation) { create_batch_safe(:reservation, restaurant: restaurant) }
    
    subject { build_clean_subject_for_validation(:table_combination, reservation: reservation) }

    describe 'name' do
      it { is_expected.to validate_presence_of(:name) }
      it { is_expected.to validate_length_of(:name).is_at_most(100) }
    end

    describe 'reservation_id uniqueness' do
      it 'validates uniqueness of reservation_id' do
        # 為同一個 reservation 創建第一個 combination
        first_combination = create_clean_table_combination(restaurant: restaurant, table_count: 2)
        
        # 嘗試為同一個 reservation 創建第二個 combination
        new_combination = build(:table_combination, :without_tables, reservation: first_combination.reservation)
        new_combination.restaurant_tables = [table1, table2]

        expect(new_combination).not_to be_valid
        expect(new_combination.errors[:reservation_id]).to include('已經被使用')
      end
    end

    describe 'custom validations' do
      describe '#must_have_at_least_two_tables' do
        it 'requires at least two tables' do
          # 使用 :without_tables trait 來避免自動建立桌位
          combination = build(:table_combination, :without_tables, reservation: reservation)
          combination.restaurant_tables = [table1]

          expect(combination).not_to be_valid
          expect(combination.errors[:restaurant_tables]).to include('併桌至少需要兩張桌位')
        end

        it 'allows two or more tables' do
          combination = build(:table_combination, :without_tables, reservation: reservation)
          combination.restaurant_tables = [table1, table2]

          expect(combination).to be_valid
        end
      end

      describe '#tables_must_be_combinable (at association level)' do
        let(:non_combinable_table) { create(:table, restaurant: restaurant, table_group: table_group, can_combine: false, table_number: 'NC1') }

        it 'rejects non-combinable tables through association validation' do
          combination = build(:table_combination, :without_tables, reservation: reservation)
          combination.restaurant_tables = [table1, non_combinable_table]

          # Try to save to trigger all validations
          combination.save
          expect(combination).not_to be_valid
          
          # The error should be in the nested table_combination_tables
          expect(combination.errors.full_messages).to include('Table combination tables is invalid')
        end

        it 'allows combinable tables' do
          combination = build(:table_combination, :without_tables, reservation: reservation)
          combination.restaurant_tables = [table1, table2]

          expect(combination).to be_valid
        end
      end

      describe '#custom_validation_logic (tested with validation integration)' do
        it 'demonstrates validation works for compatible tables' do
          combination = build(:table_combination, :without_tables, reservation: reservation)
          combination.restaurant_tables = [table1, table2]

          expect(combination).to be_valid
        end

        it 'validates minimum table requirement' do
          combination = build(:table_combination, :without_tables, reservation: reservation)
          combination.restaurant_tables = [table1]

          expect(combination).not_to be_valid
          expect(combination.errors[:restaurant_tables]).to include('併桌至少需要兩張桌位')
        end

        it 'validates non-combinable tables at association level' do
          non_combinable_table = create(:table, restaurant: restaurant, table_group: table_group, can_combine: false, table_number: 'T3')
          combination = build(:table_combination, :without_tables, reservation: reservation)
          combination.restaurant_tables = [table1, non_combinable_table]

          combination.save
          expect(combination).not_to be_valid
          expect(combination.errors.full_messages).to include('Table combination tables is invalid')
        end
      end
    end
  end

  # 3. Scope 測試
  describe 'scopes' do
    let!(:restaurant) { create_batch_safe(:restaurant) }
    let!(:confirmed_reservation) { create_batch_safe(:reservation, :confirmed, restaurant: restaurant) }
    let!(:cancelled_reservation) { create_batch_safe(:reservation, :cancelled, restaurant: restaurant) }
    let!(:active_combination) { create_clean_table_combination(restaurant: restaurant, table_count: 2) }
    let!(:inactive_combination) { create_clean_table_combination(restaurant: restaurant, table_count: 2) }

    before do
      # 設定正確的預約狀態
      active_combination.reservation.update!(status: 'confirmed')
      inactive_combination.reservation.update!(status: 'cancelled')
    end

    describe '.active' do
      it 'returns only combinations with confirmed reservations' do
        expect(TableCombination.active).to include(active_combination)
        expect(TableCombination.active).not_to include(inactive_combination)
      end
    end
  end

  # 4. 實例方法測試
  describe 'instance methods' do
    # 使用 create_clean_table_combination 輔助方法
    let(:combination) { create_clean_table_combination(table_count: 2) }

    describe '#total_capacity' do
      it 'returns sum of all table capacities' do
        expect(combination.total_capacity).to eq(8) # 4 + 4 (兩張相同容量的桌子)
      end

      it 'returns 0 when no tables' do
        empty_combination = create_clean_table_combination(table_count: 0)
        expect(empty_combination.total_capacity).to eq(0)
      end
    end

    describe '#table_numbers' do
      it 'returns comma-separated table numbers' do
        # 檢查是否包含正確數量的桌位，不依賴具體桌號
        table_numbers = combination.table_numbers
        expect(table_numbers).to include(',') # 確保有多個桌位
        expect(table_numbers.split(', ').length).to eq(2) # 確保有2張桌位
      end

      it 'returns empty string when no tables' do
        empty_combination = create_clean_table_combination(table_count: 0)
        expect(empty_combination.table_numbers).to eq('')
      end
    end

    describe '#can_accommodate?' do
      it 'returns true when party size fits total capacity' do
        expect(combination.can_accommodate?(6)).to be true
        expect(combination.can_accommodate?(8)).to be true
      end

      it 'returns false when party size exceeds total capacity' do
        expect(combination.can_accommodate?(9)).to be false
        expect(combination.can_accommodate?(15)).to be false
      end

      it 'handles zero party size' do
        expect(combination.can_accommodate?(0)).to be true
      end
    end

    describe '#display_name' do
      it 'returns name when present' do
        expect(combination.display_name).to eq('測試併桌')
      end

      it 'returns generated name when name is blank' do
        combination.name = ''
        display_name = combination.display_name
        expect(display_name).to start_with('併桌 ')
        expect(display_name).to include(',') # 確保包含桌號列表
      end

      it 'returns generated name when name is nil' do
        combination.name = nil
        display_name = combination.display_name
        expect(display_name).to start_with('併桌 ')
        expect(display_name).to include(',') # 確保包含桌號列表
      end
    end
  end

  # 5. 整合測試
  describe 'integration scenarios' do
    let(:restaurant) { create(:restaurant) }
    let(:table_group) { create(:table_group, restaurant: restaurant, name: '大廳區') }
    let(:reservation) do
      # Create reservation with save!(validate: false) to bypass complex validations
      reservation = build(:reservation, :future_datetime, restaurant: restaurant, party_size: 8, adults_count: 6, children_count: 2)
      reservation.save!(validate: false)
      reservation
    end

    context 'creating a table combination for large party' do
      let(:table1) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, max_capacity: 4, can_combine: true, table_number: 'A1') }
      let(:table2) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, max_capacity: 4, can_combine: true, table_number: 'A2') }
      let(:table3) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 6, max_capacity: 6, can_combine: true, table_number: 'A3') }

      it 'successfully creates combination with valid tables' do
        expect do
          combination = build(:table_combination, :without_tables, reservation: reservation, name: '大型聚會併桌')
          combination.restaurant_tables = [table1, table2, table3]
          combination.save!
        end.to change(TableCombination, :count).by(1)
      end

      it 'automatically creates table_combination_tables associations' do
        combination = build(:table_combination, :without_tables, reservation: reservation)
        combination.restaurant_tables = [table1, table2]
        combination.save!

        expect(combination.table_combination_tables.count).to eq(2)
        expect(combination.restaurant_tables).to include(table1, table2)
      end

      it 'provides adequate capacity for large parties' do
        combination = build(:table_combination, :without_tables, reservation: reservation)
        combination.restaurant_tables = [table1, table2, table3]
        combination.save!

        expect(combination.total_capacity).to eq(14) # 4 + 4 + 6
        expect(combination.can_accommodate?(8)).to be true
      end
    end

    context 'validation enforcement workflow' do
      let(:table1) { create(:table, restaurant: restaurant, table_group: table_group, can_combine: true) }
      let(:table2) { create(:table, restaurant: restaurant, table_group: table_group, can_combine: true) }

      it 'prevents combinations with insufficient tables' do
        combination = build(:table_combination, :without_tables, reservation: reservation)
        combination.restaurant_tables = [table1] # Only one table

        expect(combination).not_to be_valid
        expect(combination.errors[:restaurant_tables]).to include('併桌至少需要兩張桌位')
      end

      it 'prevents duplicate combinations for same reservation' do
        # 創建第一個有桌位的 combination
        first_combination = create_clean_table_combination
        
        # 嘗試為同一個 reservation 創建重複的 combination
        duplicate_combination = build(:table_combination, :without_tables, reservation: first_combination.reservation)
        duplicate_combination.restaurant_tables = [
          create(:table, restaurant: first_combination.reservation.restaurant, table_group: first_combination.restaurant_tables.first.table_group, can_combine: true),
          create(:table, restaurant: first_combination.reservation.restaurant, table_group: first_combination.restaurant_tables.first.table_group, can_combine: true)
        ]

        expect(duplicate_combination).not_to be_valid
        expect(duplicate_combination.errors[:reservation_id]).to include('已經被使用')
      end
    end

    context 'realistic business scenarios' do
      let(:table_group) { create(:table_group, restaurant: restaurant, name: '包廂區') }

      before do
        # Create tables with different capacities and statuses
        @table1 = create(:table, restaurant: restaurant, table_group: table_group,
                                 capacity: 4, max_capacity: 4, can_combine: true, table_number: 'A1')
        @table2 = create(:table, restaurant: restaurant, table_group: table_group,
                                 capacity: 4, max_capacity: 4, can_combine: true, table_number: 'A2')
        @table3 = create(:table, restaurant: restaurant, table_group: table_group,
                                 capacity: 6, max_capacity: 6, can_combine: true, table_number: 'A3')
      end

      it 'successfully handles typical table combination workflow' do
        # Create combination for large party
        combination = build(:table_combination, :without_tables,
                            reservation: reservation,
                            name: '大型聚會併桌',
                            notes: '慶祝活動，需要較大空間')

        combination.restaurant_tables = [@table1, @table2, @table3]

        expect(combination.save!).to be true
        expect(combination.total_capacity).to eq(14) # 4 + 4 + 6
        expect(combination.can_accommodate?(8)).to be true
        expect(combination.table_numbers).to eq('A1, A2, A3')
        expect(combination.display_name).to eq('大型聚會併桌')
      end
    end
  end
end
