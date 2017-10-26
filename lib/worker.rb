module Worker
  @queue = :default

  def self.thread_id
    "#{Process.pid}_#{Thread.current.object_id}"
  end
  
  def self.schedule_for(queue, klass, method_name, *args)
    @queue = queue.to_s
    job_hash = Digest::MD5.hexdigest(args.to_json)
    note_job(job_hash)
    size = Resque.size(queue)
    if queue == :slow
      Resque.enqueue(SlowWorker, klass.to_s, method_name, *args)
      if size > 1000 && !RedistInit.default.get("queue_warning_#{queue}")
        RedisInit.default.setex("queue_warning_#{queue}", 5.minutes.to_i, "true")
        Rails.logger.error("job queue full: #{queue}, #{size} entries")
      end
    else
      Resque.enqueue(Worker, klass.to_s, method_name, *args)
      if size > 5000 && !RedistInit.default.get("queue_warning_#{queue}")
        RedisInit.default.setex("queue_warning_#{queue}", 5.minutes.to_i, "true")
        Rails.logger.error("job queue full: #{queue}, #{size} entries")
      end
    end
  end
  
  def self.note_job(hash)
    if RedisInit.default
      timestamps = JSON.parse(RedisInit.default.hget('hashed_jobs', hash) || "[]")
      cutoff = 6.hours.ago.to_i
      timestamps = timestamps.select{|ts| ts > cutoff }
      timestamps.push(Time.now.to_i)
      RedisInit.default.hset('hashed_jobs', hash, timestamps.to_json)
    end
  end
  
  def self.clear_job(hash)
    if RedisInit.default
      timestamps = JSON.parse(RedisInit.default.hget('hashed_jobs', hash) || "[]")
      timestamps.shift
      RedisInit.default.hset('hashed_jobs', hash, timestamps.to_json)
    end
  end
  
  def self.schedule(klass, method_name, *args)
    schedule_for(:default, klass, method_name, *args)
  end
  
  def self.perform(*args)
    perform_at(:normal, *args)
  end
  
  def self.ts
    Time.now.to_i
  end
  
  def self.in_worker_process?
    PaperTrail.whodunnit && PaperTrail.whodunnit.match(/^job/)
  end
  
  def self.perform_at(speed, *args)
    args_copy = [] + args
    klass_string = args_copy.shift
    klass = Object.const_get(klass_string)
    method_name = args_copy.shift
    job_hash = Digest::MD5.hexdigest(args_copy.to_json)
    hash = args_copy[0] if args_copy[0].is_a?(Hash)
    hash ||= {'method' => method_name}
    action = "#{klass_string} . #{hash['method']} (#{hash['id']})"
    pre_whodunnit = PaperTrail.whodunnit
    PaperTrail.whodunnit = "job:#{action}"
    Rails.logger.info("performing #{action}")
    start = self.ts
    klass.send(method_name, *args_copy)
    diff = self.ts - start
    Rails.logger.info("done performing #{action}, finished in #{diff}s")
    # TODO: way to track what queue a job is coming from
    if diff > 60 && speed == :normal
      Rails.logger.error("long-running job, #{action}, #{diff}s")
    elsif diff > 60*10 && speed == :slow
      Rails.logger.error("long-running job, #{action} (expected slow), #{diff}s")
    end
    PaperTrail.whodunnit = pre_whodunnit
    clear_job(job_hash)
  rescue Resque::TermException
    Resque.enqueue(self, *args)
  end
  
  def self.on_failure_retry(e, *args)
    # TODO...
  end
  
  def self.scheduled_actions(queue='default')
    queues = [queue]
    if queue == '*'
      queues = []
      Resque.queues.each do |key|
        queues << key
      end
    end

    res = []
    queues.each do |queue|
      idx = Resque.size(queue)
      idx.times do |i|
        res << Resque.peek(queue, i)
      end
    end
    res
  end
  
  def self.scheduled_for?(queue, klass, method_name, *args)
    idx = Resque.size(queue)
    queue_class = (queue == :slow ? 'SlowWorker' : 'Worker')
    if false
      job_hash = args.to_json
      timestamps = JSON.parse(RedisInit.default.hget('hashed_jobs', job_hash) || "[]")
      cutoff = 6.hours.ago.to_i
      return timestamps.select{|ts| ts > cutoff }.length > 0
    else
      start = 0
      while start < idx
        items = Resque.peek(queue, start, 1000)
        start += items.length > 0 ? items.length : 1
        items.each do |schedule|
          if schedule && schedule['class'] == queue_class && schedule['args'][0] == klass.to_s && schedule['args'][1] == method_name.to_s
            if args.to_json == schedule['args'][2..-1].to_json
              return true
            end
          end
        end
      end
    end
    return false
  end
  
  def self.scheduled?(klass, method_name, *args)
    scheduled_for?('default', klass, method_name, *args)
  end
  
  def self.stop_stuck_workers
    timeout = 8.hours.to_i
    Resque.workers.each {|w| w.unregister_worker if w.processing['run_at'] && Time.now - w.processing['run_at'].to_time > timeout}    
  end
  
  def self.prune_dead_workers
    Resque.workers.each{|w| w.prune_dead_workers }
  end
  
  def self.kill_all_workers
    Resque.workers.each{|w| w.unregister_worker }
  end
  
  def self.process_queues
    schedules = []
    Resque.queues.each do |key|
      while Resque.size(key) > 0
        schedules << {queue: key, action: Resque.pop(key)}
      end
    end
    schedules.each do |schedule|
      queue = schedule[:queue]
      schedule  = schedule[:action]
      if queue == 'slow'
        raise "unknown job: #{schedule.to_json}" if schedule['class'] != 'SlowWorker'
        SlowWorker.perform(*(schedule['args']))
      else
        raise "unknown job: #{schedule.to_json}" if schedule['class'] != 'Worker'
        Worker.perform(*(schedule['args']))
      end
    end
  end
  
  def self.queues_empty?
    found = false
    Resque.queues.each do |key|
      return false if Resque.size(key) > 0
    end
    true
  end
  
  def self.flush_queues
    if Resque.redis
      Resque.queues.each do |key|
        Resque.redis.ltrim("queue:#{key}", 1, 0)
      end
    end
    RedisInit.default.del('hashed_jobs')
  end
end