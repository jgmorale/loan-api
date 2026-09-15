class CreatePayments < ActiveRecord::Migration[7.0]
  def change
    create_table :payments do |t|
      t.bigint :folio_id, null: false
      t.references :loan, null: false, foreign_key: true
      t.decimal :amount, null: false, precision: 15, scale: 2
      t.string :status, null: false, default: "created"

      t.timestamps
    end

    add_index :payments, [:folio_id, :loan_id], unique: true
  end
end