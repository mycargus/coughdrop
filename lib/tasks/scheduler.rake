desc "This task is called by the Heroku scheduler add-on"

task :check_for_expiring_subscriptions => :environment do
  puts "Checking for expiring subscriptions..."
  res = User.check_for_subscription_updates
  puts "done."
  puts JSON.pretty_generate(res)
end

task :generate_log_summaries => :environment do
  puts "Generating log summaries..."
  res = LogSession.generate_log_summaries
  puts "done. found #{res[:found]}, notified #{res[:notified]}"
end

task :push_remote_logs => :environment do
  puts "Finding and pushing remote logs..."
  res = LogSession.push_logs_remotely
  puts "done. updated #{res} logs"
end

task :clean_old_deleted_boards => :environment do
  puts "Cleaning old deleted boards..."
  count = DeletedBoard.flush_old_records
  puts "done, #{count} deleted."
end

task :advance_goals => :environment do
  puts "Advancing goals..."
  count = UserGoal.advance_goals.count
  puts "done, #{count} advanced."
end

task :transcode_errored_records => :environment do
  puts "Transcoding records that didn't get properly transcoded"
  count = ButtonSound.schedule_missing_transcodings
  puts "done, #{count} scheduled"
end