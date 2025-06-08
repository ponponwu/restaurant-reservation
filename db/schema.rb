# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2025_06_08_130331) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "blacklists", force: :cascade do |t|
    t.bigint "restaurant_id", null: false
    t.string "customer_name", null: false
    t.string "customer_phone", null: false
    t.text "reason"
    t.bigint "added_by_id", null: false
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_blacklists_on_active"
    t.index ["added_by_id"], name: "index_blacklists_on_added_by_id"
    t.index ["customer_phone"], name: "index_blacklists_on_customer_phone"
    t.index ["restaurant_id", "customer_phone"], name: "index_blacklists_on_restaurant_id_and_customer_phone", unique: true
    t.index ["restaurant_id"], name: "index_blacklists_on_restaurant_id"
  end

  create_table "business_periods", force: :cascade do |t|
    t.bigint "restaurant_id", null: false
    t.string "name"
    t.time "start_time"
    t.time "end_time"
    t.json "days_of_week"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "display_name"
    t.json "reservation_settings"
    t.integer "status"
    t.integer "days_of_week_mask", default: 0, null: false
    t.index ["days_of_week_mask"], name: "index_business_periods_on_days_of_week_mask"
    t.index ["restaurant_id"], name: "index_business_periods_on_restaurant_id"
  end

  create_table "closure_dates", force: :cascade do |t|
    t.bigint "restaurant_id", null: false
    t.date "date", null: false
    t.string "reason"
    t.integer "closure_type", default: 0
    t.boolean "all_day", default: true
    t.time "start_time"
    t.time "end_time"
    t.boolean "recurring", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "weekday", comment: "0-6 表示週日到週六"
    t.index ["closure_type"], name: "index_closure_dates_on_closure_type"
    t.index ["date"], name: "index_closure_dates_on_date"
    t.index ["restaurant_id", "date"], name: "index_closure_dates_on_restaurant_id_and_date"
    t.index ["restaurant_id"], name: "index_closure_dates_on_restaurant_id"
    t.index ["weekday"], name: "index_closure_dates_on_weekday"
  end

  create_table "reservation_policies", force: :cascade do |t|
    t.bigint "restaurant_id", null: false
    t.integer "advance_booking_days", default: 30
    t.integer "minimum_advance_hours", default: 2
    t.integer "max_party_size", default: 10
    t.integer "min_party_size", default: 1
    t.text "no_show_policy"
    t.text "modification_policy"
    t.boolean "deposit_required", default: false
    t.decimal "deposit_amount", precision: 10, scale: 2, default: "0.0"
    t.boolean "deposit_per_person", default: false
    t.json "special_rules"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "cancellation_hours", default: 24
    t.index ["restaurant_id"], name: "index_reservation_policies_on_restaurant_id"
  end

  create_table "reservation_slots", force: :cascade do |t|
    t.bigint "business_period_id", null: false
    t.time "slot_time", null: false
    t.integer "max_capacity", default: 0
    t.integer "interval_minutes", default: 30
    t.integer "reservation_deadline", default: 60
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_period_id", "slot_time"], name: "index_reservation_slots_on_business_period_id_and_slot_time", unique: true
    t.index ["business_period_id"], name: "index_reservation_slots_on_business_period_id"
    t.index ["slot_time"], name: "index_reservation_slots_on_slot_time"
  end

  create_table "reservations", force: :cascade do |t|
    t.bigint "restaurant_id", null: false
    t.bigint "table_id"
    t.bigint "business_period_id", null: false
    t.string "customer_name"
    t.string "customer_phone"
    t.string "customer_email"
    t.integer "party_size"
    t.datetime "reservation_datetime"
    t.text "special_requests"
    t.string "status"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "adults_count", default: 1, null: false
    t.integer "children_count", default: 0, null: false
    t.index ["business_period_id"], name: "index_reservations_on_business_period_id"
    t.index ["restaurant_id"], name: "index_reservations_on_restaurant_id"
    t.index ["table_id"], name: "index_reservations_on_table_id"
  end

  create_table "restaurant_tables", force: :cascade do |t|
    t.bigint "restaurant_id", null: false
    t.bigint "table_group_id"
    t.string "table_number"
    t.integer "capacity"
    t.integer "min_capacity"
    t.integer "max_capacity"
    t.string "table_type"
    t.integer "sort_order"
    t.string "status"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true, null: false
    t.boolean "can_combine", default: false, null: false
    t.string "operational_status", default: "normal", null: false
    t.index ["capacity"], name: "index_restaurant_tables_on_capacity"
    t.index ["operational_status"], name: "index_restaurant_tables_on_operational_status"
    t.index ["restaurant_id", "table_group_id"], name: "index_restaurant_tables_on_restaurant_id_and_table_group_id"
    t.index ["restaurant_id", "table_number"], name: "index_restaurant_tables_on_restaurant_id_and_table_number", unique: true
    t.index ["restaurant_id"], name: "index_restaurant_tables_on_restaurant_id"
    t.index ["status"], name: "index_restaurant_tables_on_status"
    t.index ["table_group_id"], name: "index_restaurant_tables_on_table_group_id"
  end

  create_table "restaurants", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.string "phone"
    t.text "address"
    t.json "settings"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.integer "total_capacity", default: 0, null: false
    t.string "slug", null: false
    t.integer "reservation_interval_minutes", default: 30, null: false
    t.index ["active"], name: "index_restaurants_on_active"
    t.index ["deleted_at"], name: "index_restaurants_on_deleted_at"
    t.index ["name"], name: "index_restaurants_on_name"
    t.index ["slug"], name: "index_restaurants_on_slug", unique: true
    t.index ["total_capacity"], name: "index_restaurants_on_total_capacity"
  end

  create_table "table_combination_tables", force: :cascade do |t|
    t.bigint "table_combination_id", null: false
    t.bigint "restaurant_table_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["restaurant_table_id"], name: "index_table_combination_tables_on_restaurant_table_id"
    t.index ["table_combination_id"], name: "index_table_combination_tables_on_table_combination_id"
  end

  create_table "table_combinations", force: :cascade do |t|
    t.bigint "reservation_id", null: false
    t.string "name"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reservation_id"], name: "index_table_combinations_on_reservation_id"
  end

  create_table "table_groups", force: :cascade do |t|
    t.bigint "restaurant_id", null: false
    t.string "name"
    t.text "description"
    t.integer "sort_order"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["restaurant_id"], name: "index_table_groups_on_restaurant_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "first_name"
    t.string "last_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true
    t.datetime "deleted_at"
    t.bigint "restaurant_id"
    t.integer "role", default: 2, null: false
    t.index ["active"], name: "index_users_on_active"
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["restaurant_id"], name: "index_users_on_restaurant_id"
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "blacklists", "restaurants"
  add_foreign_key "blacklists", "users", column: "added_by_id"
  add_foreign_key "business_periods", "restaurants"
  add_foreign_key "closure_dates", "restaurants"
  add_foreign_key "reservation_policies", "restaurants"
  add_foreign_key "reservation_slots", "business_periods"
  add_foreign_key "reservations", "business_periods"
  add_foreign_key "reservations", "restaurant_tables", column: "table_id"
  add_foreign_key "reservations", "restaurants"
  add_foreign_key "restaurant_tables", "restaurants"
  add_foreign_key "restaurant_tables", "table_groups"
  add_foreign_key "table_combination_tables", "restaurant_tables"
  add_foreign_key "table_combination_tables", "table_combinations"
  add_foreign_key "table_combinations", "reservations"
  add_foreign_key "table_groups", "restaurants"
  add_foreign_key "users", "restaurants"
end
