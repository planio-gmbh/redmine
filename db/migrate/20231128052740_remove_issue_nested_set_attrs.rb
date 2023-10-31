class RemoveIssueNestedSetAttrs < ActiveRecord::Migration[6.1]
  def change
    remove_column :issues, :root_id, :integer
    remove_column :issues, :lft, :integer
    remove_column :issues, :rgt, :integer
  end
end
