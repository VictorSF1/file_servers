class FileServer < ActiveRecord::Base
  unloadable
  # include Redmine::SafeAttributes

  has_many :projects, :dependent => :nullify
  has_many :attachment, :dependent => :nullify

  store :format_store
  store_accessor :format_store, :sudo_login, :sudo_password

  PROTOCOL_FTP = 0

  PROTOCOLS = { PROTOCOL_FTP => { :name => "ftp", :label => :label_file_server_ftp, :order => 1}
  }.freeze


  validates_presence_of :name
  validates_length_of :name, :maximum => 50
  validates_presence_of :address
  validates_length_of :address, :maximum => 120
  validates_numericality_of :port, :allow_nil => true
  validates_length_of :root, :maximum => 120
  validates_length_of :login, :maximum => 40
  validates_length_of :password, :maximum => 40
  validates_inclusion_of :protocol, :in => PROTOCOLS.keys

  #attr_accessible :name, :protocol, :address, :port, :root, :login, :password,
  #                :autoscan, :is_public, :project_ids, :ftp_active, :sudo_login,
  #                :sudo_password, :if => lambda {|project, user| user.admin? }

  require 'net/ftp'
  require 'stringio'
  # require 'uri'

  def initialize(attributes=nil, *args)
    super
    if new_record?
      # set default values for new records only
      self.protocol ||= PROTOCOLS.keys[0]
    end
  end

  def to_s; self.name end

  def type_name
    PROTOCOLS[self.protocol][:name]
  end

  def type_label
    l(PROTOCOLS[self.protocol ||= PROTOCOLS.keys[0]][:label])
  end

  def is_passive?
    !ftp_active
  end

  def ftp_active
    format_store[:ftp_active] == '1'
  end

  def ftp_active=(val)
    format_store[:ftp_active] = val
  end

  def ftpurl_for(relative_path,full,root_included=false,show_credentials=true)
    url = []
    if full
      ftp_credentials = "ftp://"
      if show_credentials
        ftp_credentials += self.login if self.login
        ftp_credentials += ":" + self.password if self.password && self.is_public
        ftp_credentials += "@" if self.login || (self.password && self.is_public)
      end
      ftp_credentials += self.address
      ftp_credentials += ":" + self.port.to_s unless self.port.nil?
      url << ftp_credentials
    end
    url << self.root if (!self.root.blank? && !root_included)
    url << relative_path
    logger.debug("url_for url -- #{url} ---")
    url.compact.join('/')
  end

  def make_directory(path,ftp=nil,ftp_close=true)
    ftp = ftp_connection if ftp.nil?
    return if ftp.nil?
    ret = false
    begin
      logger.debug("make_directory Change Directory - #{path}")
      begin
        ftp.chdir path
      rescue
        logger.debug("make_directory Change Directory with / - /#{path}")
        ftp.chdir "/#{path}"
      end
      ret = true
    rescue
      begin
        path.split("/").each do |d|
          logger.debug("make_directory create Directory - #{d}")
          begin
            ftp.mkdir d
          rescue
          end
          ftp.chdir d
        end
        ftp.close if ftp_close
        ret = true
      rescue Exception => e
        logger.debug("FTP FILESERVER : make_directory - #{e}")
      end
    end
    ret
  end

  def scan_directory(path,attched_files,create_it=false)
    ftp = ftp_connection
    return if ftp.nil?

    files = {}
    begin
      if create_it
        make_directory(path,ftp,false)
      else
        ftp.chdir path
      end

      ftp.passive = true if is_passive?
      # files = ftp.nlst

      ftp.nlst.each do |file|
        logger.debug("scan_directory File - #{file}")
        if !attched_files.include? file
          begin
            files[file] = ftp.size(file) # The command fails to get size of the directory.
          rescue
            files[file] = Attachment::FOLDER_FILESIZE # Assume its a directory.
          end
          logger.debug("scan_directory File Size - #{files[file]}")
        else
          files[file] = 0 # Skip getting file size
        end
      end
    rescue Exception => e
      logger.debug("FTP FILESERVER : scan_directory - #{e}")
    end
    ftp.close
    files
  end

  def upload_file(source_file_path, target_directory_path, target_file_name, ret_filesize=false)
    ftp = ftp_connection
    return if ftp.nil?
    logger.debug("upload_file - #{source_file_path} #{target_directory_path}")
    ret = false
    begin
      make_directory(target_directory_path,ftp,false)
      begin
        ftp.chdir target_directory_path
      rescue
        logger.debug("upload_file Change Directory with / - /#{target_directory_path}")
        ftp.chdir "/#{target_directory_path}"
      end
      ftp.passive = true if is_passive?
      ftp.putbinaryfile source_file_path,target_file_name
      ret = ret_filesize ? ftp.size(target_file_name) : true
    rescue Exception => e
      raise "FTP Exception: #{e}" if ret_filesize
      logger.debug("FTP FILESERVER : upload_file - #{e}")
    end
    ftp.close
    ret
  end

  def delete_file(file_directory, file_name)
    ftp = ftp_connection(true)
    return if ftp.nil?

    ret = false
    begin
      ftp.chdir file_directory
      ftp.delete file_name
      ret = true
    rescue Exception => e
      logger.debug("FTP FILESERVER : delete_file - #{e}")
    end
    ftp.close
    ret
  end

  def self.crypt_password(pwd)
    pwd.nil? ? "" : pwd
  end

  def decrypted_password
    self.password
  end

  def puttextcontent(content, remotefile)
    target_directory_path = File.dirname(remotefile)
    target_file_name      = File.basename(remotefile)
    logger.debug("puttextcontent - #{target_directory_path} #{remotefile}")
    ftp = ftp_connection
    return if ftp.nil?
    ret = false

    f = StringIO.new(content)
    begin
      make_directory(target_directory_path,ftp,false)
      ftp.storbinary("STOR " + target_file_name, f, 8192)
    rescue Exception => e
      logger.debug("FTP FILESERVER : puttextcontent - #{e}")
    ensure
      f.close
      ftp.close
      ret = true
    end
    ret
  end

  def move_file_to_dir(source_file_path,target_file_path)
    return unless source_file_path != target_file_path
    ftp = ftp_connection
    return if ftp.nil?
    ret = false
    begin
      logger.debug("move_file_to_dir source_file_path #{source_file_path} --target_file_path - #{target_file_path}")
      ftp.rename(source_file_path,target_file_path)
      ret = true
    rescue Exception => e
      logger.debug("FTP FILESERVER : move_file_to_dir - #{e}")
    end
    ftp.close
    ret
  end

  def readftpFile(ftpremotefile, localfile=nil)
    ftp = ftp_connection
    return if ftp.nil?

    ret = ""
    begin
      ret = ftp.getbinaryfile(ftpremotefile, localfile)
    rescue Exception => e
      logger.debug("FTP FILESERVER : readftpFile - #{e}")
    end
    ftp.close
    ret
  end


  def ftp_file_exists?(file_directory, filename)
    ftp = ftp_connection
    return if ftp.nil?

    ret = false
    begin
      ftp.chdir(file_directory)
      ret = true if not ftp.nlst(filename).empty?
    rescue Exception => e
      logger.debug("FTP FILESERVER : ftp_file_exists - #{e}")
    end
    ftp.close
    ret
  end

  private
  def ftp_connection(delete=false)
    ftp = nil
    begin
      ftp = Net::FTP.new
      begin
        Timeout.timeout(5) do
          if port.nil?
            ftp.connect address
          else
            ftp.connect address, port
          end
        end
        resp = if delete && sudo_login.present? && sudo_password.present?
                 ftp.login(sudo_login, sudo_password)
               else
                 ftp.login(login, decrypted_password)
               end
        logger.debug("FTP FILESERVER : ftp_connection - #{resp}")
        ftp.passive = true if is_passive?
      rescue Timeout::Error => e
        logger.debug("FTP FILESERVER : ftp_connection - #{e}")
        ftp = nil
      end
    rescue
      ftp = nil
    end
    ftp
  end
end
