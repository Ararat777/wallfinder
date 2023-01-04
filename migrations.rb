require_relative 'database'

class CreateWallsTable < ActiveRecord::Migration[7.0]
  def change
    create_table :walls do |t|
      t.integer :status, default: 0
      t.string :symbol
      t.string :price
      t.integer :side
      t.string :last_order_side
      t.bigint :update_id
      t.decimal :wall_quantity, precision: 30, scale: 10
      t.decimal :initial_quantity, precision: 15, scale: 5
      t.decimal :current_quantity, precision: 15, scale: 5

      t.belongs_to :book_order
      t.timestamps
    end
  end
end

class CreateOrdersTable < ActiveRecord::Migration[7.0]
  def change
    create_table :orders do |t|
      t.decimal :price, precision: 20, scale: 10
      t.string :side
      t.decimal :quantity, precision: 15, scale: 5
      t.string :order_type
      t.belongs_to :wall
      t.timestamps
    end
  end
end

class CreateBookOrdersTable < ActiveRecord::Migration[7.0]
  def change
    create_table :book_orders do |t|
      t.decimal :price, precision: 20, scale: 10
      t.string :side
      t.string :symbol, index: true
      t.decimal :quantity, precision: 15, scale: 5
      t.integer :status, default: 0
      t.datetime :status_changed_at
      t.timestamps
    end
  end
end
