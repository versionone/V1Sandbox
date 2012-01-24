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
@zip_file_directory = 'g:\\SQLServer2008\\V1Production\\'
@backup_file_directory = 'Database'
@installer_dir = 'Installers'
@database_dir = 'E:\\SQLSERVER2008\\Data\\MSSQL10.INST1\\MSSQL\\DATA'

@v1_instance_name = 'V1Sandbox'
@analytics_instance_name = @v1_instance_name + 'Analytics'
@datamart_instance_name = @v1_instance_name + ' to ' + @v1_instance_name + '-datamart'
@core_url = "http://prod01/#{@v1_instance_name}"

@dataloader_dir = 'C:\\Program Files\\VersionOne\\' + @datamart_instance_name

@v1_db_name = @v1_instance_name
@datamart_db_name = @v1_instance_name + '-datamart'
@analytics_db_name = @v1_instance_name + '-analytics'

@prod_backup_filename_prefix = 'V1Production'
@analytics_backup_filename_prefix = 'V1Production-analytics'
@prod_sql_restore_commandfile = 'temp.rake.data.restore.prod'
@analytics_sql_restore_commandfile = 'temp.rake.data.restore.analytics'
@sqlserver_name = ".\\SQL2008"

###############################################################################
task :default => :build

###############################################################################
desc "Builds the solution (default task)."

task :build => [:build_v1, :build_dmanalytics, :run_datamart]


task :build_v1 => [:unzip_v1, :restore_v1, :upgrade_v1]
task :build_dmanalytics => [:unzip_analytics, :restore_analytics, :upgrade_datamart, :upgrade_analytics]

task :unzip => [:unzip_v1, :unzip_analytics]

task :restore => [:restore_v1, :restore_analytics]

task :upgrade => [:upgrade_v1, :upgrade_datamart, :upgrade_analytics]

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
	puts "Extract V1Prod backup from " + zip_filename
	unzip do |zip|
		zip.unzip_path = File.join File.dirname(__FILE__), @backup_file_directory
		zip.zip_file = zip_file
	end
end

desc "Unzip the production analytics backup zipfile"
task :unzip_analytics do
	zip_filename = @analytics_backup_filename_prefix + '.zip'
	zip_file = File.join(@zip_file_directory, zip_filename)
	puts "Extract Analytics backup from " + zip_filename
	unzip do |zip|
		zip.unzip_path = File.join File.dirname(__FILE__), @backup_file_directory
		zip.zip_file = zip_file
	end
end

###############################################################################
# Restore
###############################################################################
desc "Restore the sandbox database from the produciton backup"
task :restore_v1 do
	backup_file = (Dir[File.join(File.expand_path(@backup_file_directory), @prod_backup_filename_prefix + '*.bak')]).to_s

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
		RESTORE DATABASE @dbname FROM DISK = '#{backup_file}' WITH FILE = 1, NOUNLOAD, REPLACE, STATS = 10, MOVE 'V1Production' TO '#{@database_dir}\\#{@v1_db_name}.mdf', MOVE 'V1Production_1' TO '#{@database_dir}\\#{@v1_db_name}.ldf', MOVE 'ftrow_V1Production' TO '#{@database_dir}\\#{@v1_db_name}.ndf'
	}

    f = File.open(@prod_sql_restore_commandfile, "w")
    f.write(cmd)
    f.close
    sh "sqlcmd -S #{@sqlserver_name} -i " + @prod_sql_restore_commandfile, :verbose => true
end

desc "Restore the analytics database from the backup file"
task :restore_analytics do
	backup_file = (Dir[File.join(File.expand_path(@backup_file_directory), @analytics_backup_filename_prefix + '*.bak')]).to_s

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
	setup_exe = (Dir[FileList["#{@installer_dir}/VersionOne.Setup-Ultimate*.exe"].last]).to_s
	puts "Upgrading Sandbox using " + setup_exe
	sh "#{setup_exe} http://localhost/#{@v1_instance_name} -quiet -r -AnalyticsUrl:http://prod01/#{@analytics_instance_name} -AnalyticsSigningKey:versionone"
end

desc "Upgrade Datamart"
task :upgrade_datamart do
	setup_exe = (Dir[FileList["#{@installer_dir}/Setup-VersionOne.DatamartLoader*.exe"].last]).to_s
	puts "Upgrading Datamart using " + setup_exe
	sh "#{setup_exe} \"#{@datamart_instance_name}\" /Action:Upgrade /Quiet:True"
end

desc "Upgrade Analytics"
task :upgrade_analytics do
	setup_exe = (Dir[FileList["#{@installer_dir}/Setup-VersionOne.Analytics*.exe"].last]).to_s
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
	setup_exe = (Dir[FileList["#{@installer_dir}/Setup-VersionOne.DatamartLoader*.exe"].last]).to_s
	begin
		sh "#{setup_exe} \"#{@datamart_instance_name}\" /Action:Uninstall /Quiet:True /DeleteDatabase:True"
	rescue
		puts "NOTHING TO UNINSTALL!"
	end

end

task :remove_analytics do
	setup_exe = (Dir[FileList["#{@installer_dir}/Setup-VersionOne.Analytics*.exe"].last]).to_s
	begin
		sh "#{setup_exe} #{@analytics_instance_name} /Action:Uninstall /Quiet /AnalyticsDeleteDb:true"
	rescue
		puts "NOTHING TO UNINSTALL!"
	end
end

# #############################################################################
# Install Task
# #############################################################################
task :install_datamart do
	print "Uninstall \"#{@datamart_instance_name}\"\n"
	setup_exe = (Dir[FileList["#{@installer_dir}/Setup-VersionOne.DatamartLoader*.exe"].last]).to_s
	sh "#{setup_exe} \"#{@datamart_instance_name}\" /Action:Install /Quiet:True /EnterpriseDbServer:#{@sqlserver_name} /EnterpriseDbName:#{@v1_db_name} /DatamartDbServer:#{@sqlserver_name} /DatamartDbName:#{@datamart_db_name} /AnalyticsDbServer:#{@sqlserver_name} /AnalyticsDbName:#{@analytics_db_name}"

end

task :install_analytics do
	setup_exe = (Dir[FileList["#{@installer_dir}/Setup-VersionOne.Analytics*.exe"].last]).to_s
	print "Install #{@analytics_instance_name}\n"
	sh "#{setup_exe} #{@analytics_instance_name} /Action:Install /Quiet /DatamartDbServer:#{@sqlserver_name} /DatamartDbName:#{@datamart_db_name} /AnalyticsDbServer:#{@sqlserver_name}  /AnalyticsDbName:#{@analytics_db_name} /EnterpriseUrl:#{@core_url} /SigningKey:versionone"
end
