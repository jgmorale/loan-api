class CreatePaymentApplications < ActiveRecord::Migration[7.0]
  def change
    create_table :payment_applications do |t|
      t.references :loan, null: false, foreign_key: true
      t.bigint :payment_id, null: false
      t.decimal :amount, null: false, precision: 15, scale: 2
      t.decimal :remaining_balance, null: false, precision: 15, scale: 2

      t.timestamps
    end

    add_index :payment_applications, [:loan_id, :payment_id], unique: true
  end
end