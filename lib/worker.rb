module Worker
  @queue = :default
  extend BoyBand::WorkerMethods

  def self.method_stats(queue='default')
    list = Worker.scheduled_actions(queue); list.length
    methods = {}
    list.each do |job|
      code = (job['args'][0] || 'Unknown') + "." + (job['args'][2]['method'] || 'unknown')
      methods[code] = (methods[code] || 0) + 1
    end; list.length
    puts JSON.pretty_generate(methods.to_a.sort_by(&:last))
    methods
  end
end

