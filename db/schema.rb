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

ActiveRecord::Schema[8.0].define(version: 2026_11_10_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_audit_events", force: :cascade do |t|
    t.string "run_id", null: false
    t.integer "seq", null: false
    t.string "event", null: false
    t.string "outcome", null: false
    t.jsonb "details", default: {}, null: false
    t.string "prev_digest"
    t.string "digest", null: false
    t.datetime "created_at", null: false
    t.index ["event", "created_at"], name: "index_agent_audit_events_on_event_and_created_at"
    t.index ["run_id", "seq"], name: "index_agent_audit_events_on_run_id_and_seq", unique: true
  end

  create_table "agent_memory_entries", force: :cascade do |t|
    t.string "run_id", null: false
    t.text "objective", null: false
    t.integer "seq", null: false
    t.string "kind", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "agent_name", default: "job_search", null: false
    t.index ["agent_name", "kind", "created_at"], name: "idx_on_agent_name_kind_created_at_c2292e8770"
    t.index ["kind", "created_at"], name: "index_agent_memory_entries_on_kind_and_created_at"
    t.index ["run_id", "seq"], name: "index_agent_memory_entries_on_run_id_and_seq", unique: true
  end

  create_table "agent_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "mode", null: false
    t.text "objective", null: false
    t.string "status", default: "queued", null: false
    t.string "idempotency_key", null: false
    t.string "locked_by"
    t.datetime "locked_until"
    t.integer "attempts", default: 0, null: false
    t.datetime "deadline_at"
    t.datetime "cancel_requested_at"
    t.jsonb "result", default: {}, null: false
    t.jsonb "metrics", default: {}, null: false
    t.string "error_class"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_agent_runs_on_idempotency_key", unique: true
    t.index ["status", "locked_until"], name: "index_agent_runs_on_status_and_locked_until"
  end

  create_table "job_search_operations", force: :cascade do |t|
    t.string "operation_key", null: false
    t.string "status", null: false
    t.string "lease_token"
    t.datetime "expires_at"
    t.jsonb "result"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "operation_type"
    t.string "reconciliation_token"
    t.datetime "reconciliation_expires_at"
    t.integer "reconciliation_attempts", default: 0, null: false
    t.datetime "next_reconciliation_at"
    t.string "reconciliation_dispatch_token"
    t.datetime "reconciliation_dispatch_expires_at"
    t.bigint "fencing_token", default: 0, null: false
    t.index ["operation_key"], name: "index_job_search_operations_on_operation_key", unique: true
    t.index ["status", "next_reconciliation_at"], name: "idx_job_search_reconciliation_due"
    t.index ["status", "operation_type"], name: "index_job_search_operations_on_status_and_operation_type"
  end
end
