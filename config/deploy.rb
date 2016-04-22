# config valid only for current version of Capistrano
lock '3.4.0'

set :rvm_ruby_version, '2.1.5'

set :application, 'sparc-request'
set :repo_url, 'https://github.com/uofu-ccts/sparc-request.git'

# Default branch is :master
# set :branch, "development"
set :branch, ENV['branch'] || ask('Branch: ', nil)

# Default deploy_to directory is /var/www/my_app_name
set :deploy_to, '/home/vagrant/sparc-request'

# Default value for :scm is :git
set :scm, :git

# Default value for :format is :pretty
set :format, :pretty

# Default value for :log_level is :debug
set :log_level, :debug

# Default value for :pty is false
set :pty, true

# Default value for :linked_files is []
set :linked_files, fetch(:linked_files, []).push('config/application.yml', 'config/database.yml', 'config/epic.yml', 'config/ldap.yml', 'config/cas.yml')

# Default value for linked_dirs is []
set :linked_dirs, fetch(:linked_dirs, []).push('vendor', 'themes')

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for keep_releases is 5
set :keep_releases, 5

set :rails_env, fetch(:stage)

# use copy will clone the repo and then upload the entire app to target server
# set :deploy_via, :copy
# use remote_cache require set up  ssh agent forwarding or copy private key to target server, but only update what is changed
set :deploy_via, :remote_cache

# set the locations that we will look for changed assets to determine whether to precompile
set :assets_dependencies, %w(app/assets lib/assets vendor/assets Gemfile config/routes.rb themes/assets)

class PrecompileRequired < StandardError; end

namespace :deploy do

  after :restart, :clear_cache do
    on roles(:web), in: :groups, limit: 3, wait: 10 do
      # Here we can do anything such as:
      within release_path do
        execute :rake, 'cache:clear'
      end
      execute "touch #{current_path}/tmp/restart.txt"
    end
  end

  desc 'restart passenger process'
  task :restart_passenger do
    on roles(:app) do
      execute "touch #{current_path}/tmp/restart.txt"
    end
  end

  after :finishing, :restart_passenger

  namespace :assets do
    desc 'Precompile assets locally and upload to server'
    task :precompile_locally_copy do
      on roles(:app) do
        run_locally do
          with rails_env: fetch(:rails_env) do
            execute 'rake assets:precompile'
          end
        end

        execute "cd #{release_path} && mkdir public" rescue nil
        execute "cd #{release_path} && mkdir public/assets" rescue nil
        execute 'rm -rf public/assets/*'

        upload! 'public/assets', "#{release_path}/public", recursive: true

      end
    end

    desc 'Upload themes'
    task :upload_themes do
      on roles(:app) do
        execute "rm -rf #{shared_path}/themes"
        upload! 'themes', "#{shared_path}/", recursive: true
      end
    end

    desc 'Run the precompile task locally and upload to server'
    task :precompile_locally_archive do
      on roles(:app) do
        run_locally do
          execute 'rm tmp/assets.tar.gz' rescue nil
          execute 'rm -rf public/assets/*'

          with rails_env: fetch(:rails_env) do
            execute 'rake assets:precompile'
          end

          execute 'touch assets.tar.gz && rm assets.tar.gz'
          execute 'tar zcvf assets.tar.gz public/assets/'
          execute 'mv assets.tar.gz tmp/'
        end

        # Upload precompiled assets
        execute 'rm -rf public/assets/*'
        upload! "tmp/assets.tar.gz", "#{release_path}/assets.tar.gz"
        execute "cd #{release_path} && tar zxvf assets.tar.gz && rm assets.tar.gz"
      end
    end

    desc "Precompile assets if changed"
    task :precompile_changed do
      on roles(:app) do
        within release_path do
          with rails_env: fetch(:rails_env) do
            begin

              # find the most recent release
              latest_release = capture(:ls, '-xr', releases_path).split[1]

              # precompile if this is the first deploy
              raise PrecompileRequired unless latest_release

              #
              latest_release_path = releases_path.join(latest_release)

              # precompile if the previous deploy failed to finish precompiling
              execute(:ls, latest_release_path.join('assets_manifest_backup')) rescue raise(PrecompileRequired)

              fetch(:assets_dependencies).each do |dep|
                #execute(:du, '-b', release_path.join(dep)) rescue raise(PrecompileRequired)
                #execute(:du, '-b', latest_release_path.join(dep)) rescue raise(PrecompileRequired)

                # execute raises if there is a diff
                execute(:diff, '-Naur', release_path.join(dep), latest_release_path.join(dep)) rescue raise(PrecompileRequired)
              end

              warn("-----Skipping asset precompile, no asset diff found")

              # copy over all of the assets from the last release
              execute(:cp, '-rf', latest_release_path.join('public', fetch(:assets_prefix)), release_path.join('public', fetch(:assets_prefix)))

            rescue PrecompileRequired
              warn("----Run assets precompile")

              execute(:rake, "assets:precompile")
            end
          end
        end
      end
    end
  end

end

namespace :mysql do
  desc 'Dump the production database to db/production_data.sql'
  task :dump do
    on roles("db") do
      execute "cd #{current_path} && " +
      "rake RAILS_ENV=#{fetch(:rails_env)} mysql:dump --trace"
    end
  end

  desc 'Downloads db/production_data.sql from production server to local'
  task :download_dump do
    on roles(:db) do
      download! "#{current_path}/tmp/production_data.sql.gz", "tmp/production_data.sql.gz"
    end
  end

  desc 'Cleans up dump data file'
  task :cleanup_dump do
    on roles(:db) do
      execute "rm #{current_path}/tmp/production_data.sql.gz"
    end
  end

  desc 'Dump, download and clean up'
  task :db_runner do
    on roles(:db) do
      invoke 'mysql:dump'
      invoke 'mysql:download_dump'
      invoke 'mysql:cleanup_dump'
    end
  end

end

namespace :setup do

  desc "Upload database.yml file."
  task :upload_yml do
    on roles(:app) do
      execute "mkdir -p #{shared_path}/config"
      upload! StringIO.new(File.read("config/application.yml")), "#{shared_path}/config/application.yml"
      upload! StringIO.new(File.read("config/database.yml")), "#{shared_path}/config/database.yml"
      upload! StringIO.new(File.read("config/database.yml")), "#{shared_path}/config/epic.yml"
      upload! StringIO.new(File.read("config/database.yml")), "#{shared_path}/config/ldap.yml"
    end
  end

  desc "Seed the database."
  task :seed_db do
    on roles(:app) do
      within "#{current_path}" do
        with rails_env: fetch(:rails_env) do
          execute :bundle, "install"
          execute :rake, "db:create"
          execute :rake, "db:migrate"
          execute :rake, "db:seed"
        end
      end
    end
  end

  desc "Seed the database."
  task :catalog do
    on roles(:app) do
      within "#{current_path}" do
        with rails_env: fetch(:rails_env) do
          execute :bundle, "exec rake db:seed:catalog_manager"
        end
      end
    end
  end

  desc "truncate tables."
  task :truncate do
    require 'colorize'
    def confirm
      set :confirm, ask('Confirm? (yes/no):', 'no')
    end
    def is_confirmed
      fetch(:confirm).downcase == 'yes' || fetch(:confirm).downcase == 'y'
    end
    on roles(:app) do
      within "#{current_path}" do
        with rails_env: fetch(:rails_env) do
          set :all, ask('Truncate all? (yes/no):', 'no')
          if fetch(:all).downcase == 'yes' || fetch(:all).downcase == 'y'
            puts "truncate all table. all data will be lost. please confirm".red
            confirm
            if is_confirmed
              execute :bundle, "exec rake db:truncate"
            end

          else
            set :table_name, ask('Enter the table to truncate:', nil)
            table_name = fetch(:table_name).strip
            if !table_name.empty?
              puts "exec rake db:truncate['#{table_name}']. please confirm".red
              confirm
              if is_confirmed
                execute :bundle, "exec rake db:truncate['#{table_name}']"
              end

            end
          end
        end
      end
    end
  end

  desc 'import catalogs and services'
  task :import_catalog do
    on roles(:app) do
      within "#{current_path}" do
        with rails_env: fetch(:rails_env) do
          execute :bundle, "exec rake data:import_institution_and_service"
        end
      end
    end
  end

  desc "Symlinks config files for Nginx and Unicorn."
  task :symlink_vhost do
    on roles(:root) do
      require 'erb'
      template = File.read("config/apache.conf.erb")
      domain = fetch(:domain)
      rails_env = fetch(:rails_env)
      webmaster_email = fetch(:webmaster_email)
      docroot = fetch(:docroot)
      content = ERB.new(template).result(binding)
      path = "config/apache.conf"
      File.open(path, "w") { |f| f.write content }
      upload! StringIO.new(File.read("#{path}")), "#{shared_path}/#{path}"
      sudo "ln -nfs #{shared_path}/#{path} /etc/httpd/sites-enabled/#{fetch(:application)}.conf"
   end
  end

  desc "restart apache httpd service"
  task :restart_httpd do
    on roles(:root) do
      sudo "service httpd restart"
    end
  end

end
