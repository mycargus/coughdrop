module JsonApi::Progress
  extend JsonApi::Json
  
  TYPE_KEY = 'progress'
  DEFAULT_PAGE = 10
  MAX_PAGE = 25
    
  def self.build_json(progress, args={})
    json = {}
    json['id'] = progress.global_id
    json['status_url'] = "#{JsonApi::Json.current_host}/api/v1/progress/#{json['id']}"
    json['status'] = progress.settings['state']
    if progress.started_at && !progress.finished_at && progress.updated_at && progress.updated_at < 2.hours.ago
      json['status'] = 'errored' 
      json['result'] = {'error' => 'progress job is taking too long, possibly crashed'}
    elsif progress.started_at
      json['started_at'] = progress.started_at.iso8601
    end
    if progress.finished_at
      json['finished_at'] = progress.finished_at.iso8601
      json['result'] = progress.settings['result']
    end
    json['percent'] = progress.settings['percent'] if progress.settings['percent']
    json['sub_status'] = progress.settings['message_key'] if progress.settings['message_key']
    json
  end
end