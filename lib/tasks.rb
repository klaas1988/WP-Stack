namespace :shared do
	task :make_shared_dir do
		run "if [ ! -d #{shared_path}/files ]; then mkdir -m 755 #{shared_path}/files; fi"
	end
	task :make_symlinks do
		run "if [ ! -h #{release_path}/shared ]; then ln -s #{shared_path}/files/ #{release_path}/shared; fi"
		run "for p in `find -L #{release_path} -type l`; do t=`readlink $p | grep -o 'shared/.*$'`; sudo mkdir -p #{release_path}/$t; done"
	end
end

namespace :nginx do
	desc "Restarts nginx"
	task :restart do
		run "sudo /etc/init.d/nginx restart"
	end
end

namespace :phpfpm do
  desc" Restarts PHP-FPM"
  task :restart do
    run "sudo /etc/init.d/php-fpm restart"
  end
end

namespace :git do
	desc "Updates git submodule tags"
	task :submodule_tags do
		run "if [ -d #{shared_path}/cached-copy/ ]; then cd #{shared_path}/cached-copy/ && git submodule foreach --recursive git fetch origin --tags; fi"
	end
end

namespace :memcached do
	desc "Restarts Memcached"
	task :restart do
		run "echo 'flush_all' | nc localhost 11211", :roles => [:memcached]
	end
	desc "Updates the pool of memcached servers"
	task :update do
    unless find_servers( :roles => :memcached ).empty? then
      mc_servers = '<?php return array( "' + find_servers( :roles => :memcached ).join( ':11211", "' ) + ':11211" ); ?>'
      run "echo '#{mc_servers}' > #{current_path}/memcached.php", :roles => :memcached
    end
	end
end

namespace :uploads_dir do
    desc "Replaces uploads directory with symlink to shared uploads directory"
    task :convert_to_symlink do
        run "if [ ! -L #{release_path}/wp-content/uploads ]; then rm -rf #{release_path}/wp-content/uploads; ln -s #{release_path}/shared/ #{release_path}/wp-content/uploads; fi"
    end
end

namespace :parent_dir do
    desc "Apache .htaccess file for redirecting to current release directory"
    task :create_htaccess do
        run "shared_path=\"#{shared_path}\"; "'parent_dir="${shared_path%/*}";nl=$\'\n\'; printf "<IfModule mod_rewrite.c>${nl}RewriteEngine on${nl}RewriteCond %%{REQUEST_URI} !^/current/.*\$${nl}RewriteRule ^(.*)\$ /current/\$1${nl}</IfModule>${nl}" > "${parent_dir}/.htaccess"'
    end
    desc "Sets owner of all files and folders in public_html to that of the parent folder"
    task :set_owner do
        run "shared_path=#{shared_path}; parent_dir=${shared_path%/*}; parent_owner=$(ls -l -d $parent_dir | awk '{print $3}'); parent_group=$(ls -l -d $parent_dir | awk '{print $4}'); chown -R $parent_owner:$parent_group $parent_dir'/'"
    end
end

namespace :db do
	desc "Syncs the staging database (and uploads) from production"
	task :sync, :roles => :web  do
    if stage != :staging then
      puts "[ERROR] You must run db:sync from staging with cap staging db:sync"
    else
      puts "Hang on... this might take a while."
      random = rand( 10 ** 5 ).to_s.rjust( 5, '0' )
      p = wpdb[ :production ]
      s = wpdb[ :staging ]
      puts "db:sync"
      puts stage
      run "mysqldump -u #{p[:user]} --result-file=/tmp/wpstack-#{random}.sql -h #{p[:host]} --password='#{p[:password]}' #{p[:name]}"
      run "mysql -u #{s[:user]} -h #{s[:host]} --password='#{s[:password]}' #{s[:name]} < /tmp/wpstack-#{random}.sql && rm /tmp/wpstack-#{random}.sql"
      puts "Database synced to staging"
      # memcached.restart
      puts "Memcached flushed"
      # Now to copy files
      find_servers( :roles => :web ).each do |server|
        #run "rsync -avz --delete #{production_deploy_to}/shared/files/ #{server}:#{shared_path}/files/"
        run "rsync -avz --delete #{production_deploy_to}/shared/files/ #{shared_path}/files/"
      end
    end
	end
	desc "Sets the database credentials (and other settings) in wp-config.php"
	task :make_config do
		{:'%%WP_STAGING_DOMAIN%%' => staging_domain, :'%%WP_STAGE%%' => stage, :'%%DB_NAME%%' => wpdb[stage][:name], :'%%DB_USER%%' => wpdb[stage][:user], :'%%DB_PASSWORD%%' => wpdb[stage][:password], :'%%DB_HOST%%' => wpdb[stage][:host], :'%%SECURITY_SALT%%' => security_salt}.each do |k,v|
			run "sed -i 's/#{k}/#{v}/' #{release_path}/wp-config.php", :roles => :web
		end
	end
end
