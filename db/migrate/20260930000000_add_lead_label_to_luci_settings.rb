class AddLeadLabelToLuciSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :luci_settings, :lead_label, :string
  end
end
