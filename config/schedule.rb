set :environment, 'production'
set :output, 'log/cron.log'

every :day, at: '12:00 AM' do
  command 'cd /lcboapi && RAILS_ENV=production bundle exec rake cron'
end