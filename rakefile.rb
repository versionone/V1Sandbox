require 'rake'
require 'rubygems'
require 'albacore'
require 'date'

###############################################################################
## Other Stuff we need to know
###############################################################################
@backup_date = Date.today - 1

###############################################################################
## Configurable Stuff we need to know
###############################################################################
@zip_file_directory = 'C:\\V1Sandbox\\Databases\\'
@backup_file_directory = 'Database'
@installer_dir = 'Installers'
@database_dir = 'C:\\Program Files\\Microsoft SQL Server\\MSSQL11.MSSQLSERVER\\MSSQL\\Data'

@v1_instance_name = 'V1Sandbox'
@analytics_instance_name = @v1_instance_name + 'Analytics'
@datamart_instance_name = @v1_instance_name + ' to ' + @v1_instance_name + '-datamart'
@core_url = "http://dev2012/#{@v1_instance_name}"

@dataloader_dir = 'C:\\Program Files\\VersionOne\\' + @datamart_instance_name

@v1_db_name = @v1_instance_name
@datamart_db_name = @v1_instance_name + '-datamart'
@analytics_db_name = @v1_instance_name + '-analytics'

@prod_backup_filename_prefix = 'V1Production'
@analytics_backup_filename_prefix = 'V1Production-analytics'
@prod_sql_restore_commandfile = 'temp.rake.data.restore.prod'
@analytics_sql_restore_commandfile = 'temp.rake.data.restore.analytics'
@sqlserver_name = "."

###############################################################################
task :default => :build

###############################################################################
desc "Builds the solution (default task)."

task :build => [:info_display, :build_v1, :build_dmanalytics, :run_datamart] 

task :build_v1 => [:unzip_v1, :restore_v1, :upgrade_v1]
task :build_dmanalytics => [:unzip_analytics, :restore_analytics, :upgrade_datamart, :upgrade_analytics]

task :unzip => [:unzip_v1, :unzip_analytics]

task :restore => [:info_display, :restore_v1, :restore_analytics]

task :upgrade => [:info_display, :upgrade_v1, :upgrade_analytics, :upgrade_datamart, :run_datamart]

###############################################################################
# Clean
###############################################################################
desc "Removes the existing data to prepare for a new load"
task :clean do
	puts "Clean the workspace"
	remove_dir(@backup_file_directory, true)
	remove_dir(@installer_dir, true)
	rm @prod_sql_restore_commandfile, :verbose=>false	if File.exist?(@prod_sql_restore_commandfile)
	rm @analytics_sql_restore_commandfile, :verbose=>false	if File.exist?(@analytics_sql_restore_commandfile)
	mkdir(@installer_dir)
end

###############################################################################
# UnZip
###############################################################################
desc "Unzip the production backup zipfile"
task :unzip_v1 do
	zip_filename = @prod_backup_filename_prefix + '.zip'	
	zip_file = File.join(@zip_file_directory, zip_filename)
	fail "VersionOne zip file is not available." if not File.exist?(zip_file)
	unzip_file(zip_file)
end

desc "Unzip the production analytics backup zipfile"
task :unzip_analytics do
	zip_filename = @analytics_backup_filename_prefix + '.zip'	
	zip_file = File.join(@zip_file_directory, zip_filename)
	fail "Analytics zip file is not available." if not File.exist?(zip_file)
	unzip_file(zip_file)	
end

###############################################################################
# Restore
###############################################################################
desc "Restore the sandbox database from the produciton backup"
task :restore_v1 do
	backup_file = (Dir[File.join(File.expand_path(@backup_file_directory), @prod_backup_filename_prefix + '_*.bak')])[0].to_s
	puts backup_file
	fail "No VersionOne database file to restore" if not File.exist?(backup_file)
	puts "Restore production backup file " + backup_file
	cmd = %{
		USE master
		GO
		DECLARE @dbname sysname
		SET @dbname = '#{@v1_db_name}'
		DECLARE @spid int
		SELECT @spid = min(spid) FROM master.dbo.sysprocesses where dbid = db_id('#{@v1_db_name}')
		WHILE @spid IS NOT NULL
		BEGIN
		EXECUTE ('KILL ' + @spid)
		SELECT @spid = min(spid) FROM master.dbo.sysprocesses WHERE dbid = db_id('#{@v1_db_name}') AND spid > @spid
		END
		RESTORE DATABASE @dbname FROM DISK = N'#{backup_file}' WITH FILE = 1, NOUNLOAD, REPLACE, STATS = 10,
		MOVE 'V1Production' TO '#{@database_dir}\\#{@v1_db_name}.mdf',
		MOVE 'V1Production_log' TO '#{@database_dir}\\#{@v1_db_name}.ldf',
		MOVE 'V1Production_fts' TO '#{@database_dir}\\#{@v1_db_name}.ndf'
	}.gsub('/', '\\')
    f = File.open(@prod_sql_restore_commandfile, "w")
    f.write(cmd)
    f.close    
    sh "sqlcmd -S #{@sqlserver_name} -i " + @prod_sql_restore_commandfile, :verbose => true
end

desc "Restore the analytics database from the backup file"
task :restore_analytics do
	backup_file = (Dir[File.join(File.expand_path(@backup_file_directory), @analytics_backup_filename_prefix + '*.bak')])[0].to_s
	fail "No Analytics database file to restore" if not File.exist?(backup_file)
	puts "Restore analytics backup file " + backup_file
	cmd = %{
		USE master
		GO
		DECLARE @dbname sysname
		SET @dbname = '#{@analytics_db_name}'
		DECLARE @spid int
		SELECT @spid = min(spid) FROM master.dbo.sysprocesses where dbid = db_id('#{@analytics_db_name}')
		WHILE @spid IS NOT NULL
		BEGIN
		EXECUTE ('KILL ' + @spid)
		SELECT @spid = min(spid) FROM master.dbo.sysprocesses WHERE dbid = db_id('#{@analytics_db_name}') AND spid > @spid
		END
		RESTORE DATABASE @dbname FROM DISK = '#{backup_file}' WITH FILE = 1, NOUNLOAD, REPLACE, STATS = 10, MOVE 'V1Production-analytics' TO '#{@database_dir}\\#{@analytics_db_name}.mdf', MOVE 'V1Production-analytics_log' TO '#{@database_dir}\\#{@analytics_db_name}.ldf'
	}
    f = File.open(@analytics_sql_restore_commandfile, "w")
    f.write(cmd)
    f.close    
    sh "sqlcmd -S #{@sqlserver_name} -i " + @analytics_sql_restore_commandfile, :verbose => true
end

###############################################################################
# Upgrade
###############################################################################
desc "Upgrade Ultimate"
task :upgrade_v1 do
	setup_exe = (Dir[FileList["#{@installer_dir}/VersionOne.Setup-Ultimate*.exe"].last])[0].to_s	
	puts "Upgrading Sandbox using " + setup_exe
	sh "#{setup_exe} http://localhost/#{@v1_instance_name} -quiet -r -AnalyticsUrl:http://dev2012/#{@analytics_instance_name} -AnalyticsSigningKey:versionone"
end

desc "Upgrade Datamart"
task :upgrade_datamart do
	setup_exe = (Dir[FileList["#{@installer_dir}/Setup-VersionOne.DatamartLoader*.exe"].last])[0].to_s	
	puts "Upgrading Datamart using " + setup_exe
	sh "#{setup_exe} \"#{@datamart_instance_name}\" /Action:Upgrade /Quiet:True"
end

desc "Upgrade Analytics"
task :upgrade_analytics do
	setup_exe = (Dir[FileList["#{@installer_dir}/Setup-VersionOne.Analytics*.exe"].last])[0].to_s
	puts "Upgrading Analytics using " + setup_exe
	sh "#{setup_exe} #{@analytics_instance_name} /Action:Upgrade /Quiet:True"
end

###############################################################################
# Datamart Loader
###############################################################################
desc "Execute the Datamart Loader"
task :run_datamart do 
	setup_exe = 'VersionOne.DatamartLoader.exe'	
	Dir.chdir @dataloader_dir
	sh "#{setup_exe}"
end

# #############################################################################
# Remove Task
# #############################################################################
task :remove_datamart do
	print "Uninstall \"#{@datamart_instance_name}\"\n"
	setup_exe = (Dir[FileList["#{@installer_dir}/Setup-VersionOne.DatamartLoader*.exe"].last])[0].to_s	
	begin
		sh "#{setup_exe} \"#{@datamart_instance_name}\" /Action:Uninstall /Quiet:True /DeleteDatabase:True"
	rescue
		puts "NOTHING TO UNINSTALL!"
	end
	
end

task :remove_analytics do
	setup_exe = (Dir[FileList["#{@installer_dir}/Setup-VersionOne.Analytics*.exe"].last])[0].to_s
	begin
		sh "#{setup_exe} #{@analytics_instance_name} /Action:Uninstall /Quiet /AnalyticsDeleteDb:true"
	rescue
		puts "NOTHING TO UNINSTALL!"
	end
end

# #############################################################################
# Install Task
# #############################################################################
task :install_v1 do
	setup_exe = (Dir[FileList["#{@installer_dir}/VersionOne.Setup-Ultimate*.exe"].last])[0].to_s	
	puts "Install Sandbox using " + setup_exe
	sh "#{setup_exe} http://localhost/#{@v1_instance_name} -quiet -AnalyticsUrl:http://dev2012/#{@analytics_instance_name} -AnalyticsSigningKey:versionone"
end

task :install_datamart do
	print "Install \"#{@datamart_instance_name}\"\n"
	setup_exe = (Dir[FileList["#{@installer_dir}/Setup-VersionOne.DatamartLoader*.exe"].last])[0].to_s	
	sh "#{setup_exe} \"#{@datamart_instance_name}\" /Action:Install /Quiet:True /EnterpriseDbServer:#{@sqlserver_name} /EnterpriseDbName:#{@v1_db_name} /DatamartDbServer:#{@sqlserver_name} /DatamartDbName:#{@datamart_db_name} /AnalyticsDbServer:#{@sqlserver_name} /AnalyticsDbName:#{@analytics_db_name}"

end

task :install_analytics do
	setup_exe = (Dir[FileList["#{@installer_dir}/Setup-VersionOne.Analytics*.exe"].last])[0].to_s
	print "Install #{@analytics_instance_name}\n"
	sh "#{setup_exe} #{@analytics_instance_name} /Action:Install /Quiet /DatamartDbServer:#{@sqlserver_name} /DatamartDbName:#{@datamart_db_name} /AnalyticsDbServer:#{@sqlserver_name}  /AnalyticsDbName:#{@analytics_db_name} /EnterpriseUrl:#{@core_url} /SigningKey:versionone"
end

# #############################################################################
# Utility 
# #############################################################################
def unzip_file (file)
	destination = File.join File.dirname(__FILE__), @backup_file_directory
	puts "Extract #{file} into #{destination}"
	Zip::ZipFile.open(file) { |zip_file|
		zip_file.each { |f|
			f_path=File.join(destination, f.name)
			FileUtils.mkdir_p(File.dirname(f_path))
			zip_file.extract(f, f_path) unless File.exist?(f_path)
		}
	}
end

task :info_display do
	puts ""
	puts "############################### info on this biznitch ###############################################"
	puts ""
	puts "this is running from			: " + File.expand_path(__FILE__)
	puts "target zip directory 			: " + @zip_file_directory
	puts "backup folder 				: " + @backup_file_directory
	puts "install folder 				: " + @installer_dir
	puts "database backup directory		: " + @database_dir
	puts "V1 Web Instance name 			: " + @v1_instance_name
	puts "sql server name				: " + @sqlserver_name
	puts "Analytics instance			: " + @v1_instance_name + 'Analytics'
	puts "Datamart instance name 			: " + @datamart_instance_name
	puts "url 					: " + @core_url
	puts "data loader directory			: " + @dataloader_dir
	puts "database name 				: " + @v1_db_name
	puts "datamart db name			: " + @datamart_db_name
	puts "analytics name 				: " + @analytics_db_name
	puts "prod backup filename prefix		: " + @prod_backup_filename_prefix
	puts "analytics backup filename prefix	: " + @analytics_backup_filename_prefix
	puts "production sql restore command file	: " + @prod_sql_restore_commandfile
	puts "analytics sql restore command file 	: " + @analytics_sql_restore_commandfile
	puts ""
	puts "########################## out like a fat kid in dodgeball ##########################################"
	puts ""
end



def get_user_name
  api = Win32API.new(
    'advapi32.dll',
    'GetUserName',
    'PP',
    'i'
  )

  buf = "\0" * 512
  len = [512].pack('L')
  api.call(buf,len)

  buf[0..(len.unpack('L')[0])]
end
