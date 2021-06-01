class AddFormatStoreColToFileServers < ActiveRecord::Migration[4.2]
  def change
    add_column :file_servers, :format_store, :text
  end
end
