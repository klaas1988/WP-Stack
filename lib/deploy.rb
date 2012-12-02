#
set :user, "deploy"
set :use_sudo, false
set :deploy_via, :remote_cache
set :copy_exclude, [".git", ".gitmodules", ".DS_Store", ".gitignore"]
set :keep_releases, 5

after "deploy:restart", "deploy:cleanup"
after "deploy:update_code", "shared:make_shared_dir"
after "deploy:update_code", "shared:make_symlinks"
after "deploy:update_code", "db:make_config"
after "deploy", "memcached:update"
after "deploy", "uploads_dir:convert_to_symlink"
after "deploy", "parent_dir:set_owner"

# Pull in the config file
loadFile 'config/config.rb'
