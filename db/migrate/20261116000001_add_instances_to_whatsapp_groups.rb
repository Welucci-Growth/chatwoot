# A group usually holds several staff numbers, and each Evolution instance reports it. The single
# `instance` column kept whichever number synced last, so a group could drop out of the view of
# the team that actually works in it.
class AddInstancesToWhatsappGroups < ActiveRecord::Migration[7.1]
  def up
    add_column :whatsapp_groups, :instances, :string, array: true, default: [], null: false
    execute 'UPDATE whatsapp_groups SET instances = ARRAY[instance]'
    add_index :whatsapp_groups, :instances, using: :gin
  end

  def down
    remove_column :whatsapp_groups, :instances
  end
end
