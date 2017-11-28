class AddParentOrganizationIdToOrganizations < ActiveRecord::Migration[5.0]
  def change
    add_column :organizations, :parent_organization_id, :integer
    add_index :organizations, [:parent_organization_id]
  end
end
