class CreateLoans < ActiveRecord::Migration[7.0]
  def change
    create_table :loans do |t|
      t.decimal :total, null: false, precision: 15, scale: 2
      t.string :status, null: false, default: "loan"

      t.timestamps
    end
  end
end