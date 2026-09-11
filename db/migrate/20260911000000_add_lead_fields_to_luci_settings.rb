class AddLeadFieldsToLuciSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :luci_settings, :lead_pipeline_id, :string
    add_column :luci_settings, :lead_stage_id, :string
  end
end
