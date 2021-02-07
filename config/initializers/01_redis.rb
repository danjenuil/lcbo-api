# no need to run if we are compiling assets
if ENV['ASSETS_PRECOMPILE'].blank?
  $redis = Redis.new(url: Rails.application.secrets.redis, thread_safe: true)
  $redis.ping
end
