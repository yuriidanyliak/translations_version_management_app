# README

## How to run an app:
- rvm install 2.7.1 (or whatever ruby version that works with Rails 6)
- rvm use 2.7.1@tvm --create (or whatever ruby version management tool you use)
- bundle install
- createuser -P -d tvm (set password to "tvm_password")
- rake db:create db:migrate
- rake webpacker:install
- rails s
- Navigate to http://localhost:3000
- Voilà!
