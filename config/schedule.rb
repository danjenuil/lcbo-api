set :environment, 'production'
set :output, 'log/cron.log'

every :day, at: '12:00 AM' do
  rake 'cron'
end