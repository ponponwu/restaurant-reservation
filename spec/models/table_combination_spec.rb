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
    subject { build(:table_combination, :without_tables, reservation: reservation) }

    let(:restaurant) { create(:restaurant) }
    let(:table_group) { create(:table_group, restaurant: restaurant) }
    let(:table1) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, can_combine: true) }
    let(:table2) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, can_combine: true) }
    let(:reservation) { create(:reservation, restaurant: restaurant) }

    describe 'name' do
      it { is_expected.to validate_presence_of(:name) }
      it { is_expected.to validate_length_of(:name).is_at_most(100) }
    end

    describe 'reservation_id uniqueness' do
      it 'validates uniqueness of reservation_id' do
        create(:table_combination, reservation: reservation)
        new_combination = build(:table_combination, :without_tables, reservation: reservation)

        # 手動設定桌位以通過基本驗證
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
        let(:non_combinable_table) { create(:table, restaurant: restaurant, table_group: table_group, can_combine: false) }

        it 'rejects non-combinable tables through association validation' do
          combination = build(:table_combination, :without_tables, reservation: reservation)
          combination.restaurant_tables = [table1, non_combinable_table]

          expect(combination).not_to be_valid
          # TableCombinationTable validation triggers this error
          expect(combination.errors.full_messages.any? { |msg| msg.include?('格式錯誤') }).to be true
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
          non_combinable_table = create(:table, restaurant: restaurant, table_group: table_group, can_combine: false)
          combination = build(:table_combination, :without_tables, reservation: reservation)
          combination.restaurant_tables = [table1, non_combinable_table]

          expect(combination).not_to be_valid
          expect(combination.errors.full_messages.any? { |msg| msg.include?('格式錯誤') }).to be true
        end
      end
    end
  end

  # 3. Scope 測試
  describe 'scopes' do
    let(:restaurant) { create(:restaurant) }
    let!(:confirmed_reservation) { create(:reservation, :confirmed, restaurant: restaurant) }
    let!(:cancelled_reservation) { create(:reservation, :cancelled, restaurant: restaurant) }
    let!(:active_combination) { create(:table_combination, reservation: confirmed_reservation) }
    let!(:inactive_combination) { create(:table_combination, reservation: cancelled_reservation) }

    describe '.active' do
      it 'returns only combinations with confirmed reservations' do
        expect(TableCombination.active).to include(active_combination)
        expect(TableCombination.active).not_to include(inactive_combination)
      end
    end
  end

  # 4. 實例方法測試
  describe 'instance methods' do
    subject do
      # First ensure tables are created
      table1 # Force creation
      table2 # Force creation

      # Create combination with default factory (which includes tables)
      combination = create(:table_combination, reservation: reservation, name: '特別併桌')

      # Replace the default tables with our specific ones
      combination.restaurant_tables.clear
      combination.restaurant_tables = [table1, table2]
      combination.save!
      combination
    end

    let(:restaurant) { create(:restaurant) }
    let(:table_group) { create(:table_group, restaurant: restaurant) }
    let(:table1) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, table_number: 'T1', can_combine: true) }
    let(:table2) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 6, max_capacity: 6, table_number: 'T2', can_combine: true) }
    let(:reservation) { create(:reservation, restaurant: restaurant) }

    describe '#total_capacity' do
      it 'returns sum of all table capacities' do
        expect(subject.total_capacity).to eq(10) # 4 + 6
      end

      it 'returns 0 when no tables' do
        combination = create(:table_combination, reservation: reservation)
        combination.restaurant_tables.clear
        expect(combination.total_capacity).to eq(0)
      end
    end

    describe '#table_numbers' do
      it 'returns comma-separated table numbers' do
        expect(subject.table_numbers).to eq('T1, T2')
      end

      it 'returns empty string when no tables' do
        combination = create(:table_combination, reservation: reservation)
        combination.restaurant_tables.clear
        expect(combination.table_numbers).to eq('')
      end
    end

    describe '#can_accommodate?' do
      it 'returns true when party size fits total capacity' do
        expect(subject.can_accommodate?(8)).to be true
        expect(subject.can_accommodate?(10)).to be true
      end

      it 'returns false when party size exceeds total capacity' do
        expect(subject.can_accommodate?(11)).to be false
        expect(subject.can_accommodate?(15)).to be false
      end

      it 'handles zero party size' do
        expect(subject.can_accommodate?(0)).to be true
      end
    end

    describe '#display_name' do
      it 'returns name when present' do
        expect(subject.display_name).to eq('特別併桌')
      end

      it 'returns generated name when name is blank' do
        subject.name = ''
        expect(subject.display_name).to eq('併桌 T1, T2')
      end

      it 'returns generated name when name is nil' do
        subject.name = nil
        expect(subject.display_name).to eq('併桌 T1, T2')
      end
    end
  end

  # 5. 整合測試
  describe 'integration scenarios' do
    let(:restaurant) { create(:restaurant) }
    let(:table_group) { create(:table_group, restaurant: restaurant, name: '大廳區') }
    let(:reservation) { create(:reservation, restaurant: restaurant, party_size: 8, adults_count: 6, children_count: 2) }

    context 'creating a table combination for large party' do
      let(:table1) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, can_combine: true, table_number: 'A1') }
      let(:table2) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, can_combine: true, table_number: 'A2') }
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
        create(:table_combination, reservation: reservation)

        duplicate_combination = build(:table_combination, :without_tables, reservation: reservation)
        duplicate_combination.restaurant_tables = [table1, table2] # 設定桌位以通過基本驗證

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
                                 capacity: 4, max_capacity: 6, can_combine: true, table_number: 'A2')
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
