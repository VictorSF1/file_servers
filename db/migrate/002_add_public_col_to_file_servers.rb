class AddPublicColToFileServers < ActiveRecord::Migration[4.2]
  def change
    add_column :file_servers, :is_public, :boolean
  end
end
