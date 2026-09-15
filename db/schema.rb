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

ActiveRecord::Schema[7.0].define(version: 2026_09_14_000003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "loans", force: :cascade do |t|
    t.decimal "total", precision: 15, scale: 2, null: false
    t.string "status", default: "loan", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "outbox_events", force: :cascade do |t|
    t.uuid "event_id", null: false
    t.string "event_name", null: false
    t.string "aggregate_type", null: false
    t.bigint "aggregate_id", null: false
    t.jsonb "body", null: false
    t.datetime "occurred_at", null: false
    t.datetime "published_at"
    t.integer "attempts", default: 0, null: false
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_outbox_events_on_event_id", unique: true
    t.index ["published_at", "created_at"], name: "index_outbox_events_on_published_at_and_created_at"
  end

  create_table "payment_applications", force: :cascade do |t|
    t.bigint "loan_id", null: false
    t.bigint "payment_id", null: false
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.decimal "remaining_balance", precision: 15, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["loan_id", "payment_id"], name: "index_payment_applications_on_loan_id_and_payment_id", unique: true
    t.index ["loan_id"], name: "index_payment_applications_on_loan_id"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "folio_id", null: false
    t.bigint "loan_id", null: false
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.string "status", default: "created", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["folio_id", "loan_id"], name: "index_payments_on_folio_id_and_loan_id", unique: true
    t.index ["loan_id"], name: "index_payments_on_loan_id"
  end

  add_foreign_key "payment_applications", "loans"
  add_foreign_key "payments", "loans"
end
