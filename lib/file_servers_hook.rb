class FileServerHook  < Redmine::Hook::ViewListener

  def view_layouts_base_html_head(context = {})
   	stylesheet_link_tag('file_servers', :plugin => 'file_servers')
  end

end