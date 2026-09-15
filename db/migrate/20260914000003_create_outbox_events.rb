class CreateOutboxEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :outbox_events do |t|
      t.uuid :event_id, null: false
      t.string :event_name, null: false
      t.string :aggregate_type, null: false
      t.bigint :aggregate_id, null: false
      t.jsonb :body, null: false
      t.datetime :occurred_at, null: false
      t.datetime :published_at
      t.integer :attempts, null: false, default: 0
      t.text :last_error

      t.timestamps
    end

    add_index :outbox_events, :event_id, unique: true
    add_index :outbox_events, [:published_at, :created_at]
  end
end