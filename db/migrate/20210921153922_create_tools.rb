class CreateTools < ActiveRecord::Migration[6.1]
  def change
    create_table :tools do |t|
      t.string :name, null: false
      t.string :language, null: false
      t.json :json_spec

      t.timestamps
    end
  end
end
