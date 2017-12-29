module UpstreamDownstream
  extend ActiveSupport::Concern
  
  def track_downstream_boards!(already_visited_ids=[], buttons_changed=false, trigger_stamp=nil)
    # short-circuit if board has been tracked by another process since this was originally scheduled
    return if self.class.last_scheduled_stamp && self.settings['last_tracked'] && self.settings['last_tracked'] > self.class.last_scheduled_stamp
    @track_downstream_boards = true
    Rails.logger.info("touching downstreams #{self.global_id}")
    self.touch_downstreams(already_visited_ids)
    self.track_downstream_boards(already_visited_ids, buttons_changed, trigger_stamp)
    Rails.logger.info("touching downstreams again #{self.global_id}")
    self.touch_downstreams(already_visited_ids)
    @track_downstream_boards = false
    true
  end
  
  def edit_stats
    {
      'total_buttons' => self.settings['buttons'].length,
      'unlinked_buttons' => self.settings['buttons'].select{|btn| !btn['load_board'] }.length,
      'current_revision' => self.current_revision
    }
  end
  
  def track_downstream_boards(already_visited_ids=[], buttons_changed=false, trigger_stamp=nil)
    return unless @track_downstream_boards
    return if already_visited_ids.include?(self.global_id)
    already_visited_ids << self.global_id
    trigger_stamp ||= Time.now.to_i

    top_board = self
    # step 1: travel downstream, for every board id get its immediate children
    Rails.logger.info('getting all children')
    boards_with_children = {}
    board_edit_stats = {}
    unfound_boards = ["self"]

    # short-circuit individual lookups, since the board most likely already knows about most of
    # its downstreams, and only one or a few will be new or updated    
    Board.find_all_by_global_id(self.settings['downstream_board_ids'] || []).each do |board|
      id = board.global_id
      # also track button counts, used for board stats
      board_edit_stats[id] = board.edit_stats
      boards_with_children[id] = (board.settings['immediately_downstream_board_ids'] || [])
    end
    unfound_boards += boards_with_children.map(&:last).flatten - boards_with_children.keys
    
    while !unfound_boards.empty?
      id = unfound_boards.shift
      board = top_board 
      if id != "self"
        board = Board.find_by_path(id)
        board.reload if board
      end
      if board
        children_ids = []
        # also track button counts, used for board stats
        board_edit_stats[id] = board.edit_stats
        downs = (board.settings['immediately_downstream_board_ids'] || [])
        downs.each do |child_id|
          children_ids << child_id
          if !boards_with_children[child_id]
            unfound_boards << child_id
          end
        end
        boards_with_children[id] = children_ids
      end
    end
    
    # step 2: the complete downstream list is a collection of all these ids
    Rails.logger.info('generating stats and revision keys')
    downs = []
    boards_with_children.each do |id, children|
      downs += children
    end
    downs = downs.uniq.sort - [top_board.global_id]
    changed = (downs != (top_board.settings['downstream_board_ids'] || []).uniq.sort)
    total_buttons = 0
    unlinked_buttons = 0
    revision_hashes = [top_board.current_revision]
    # TODO: track last edit date for board and any sub-board (not the same as updated_at)
    downs.each do |id|
      if board_edit_stats[id]
        total_buttons += board_edit_stats[id]['total_buttons']
        unlinked_buttons += board_edit_stats[id]['unlinked_buttons']
        revision_hashes << board_edit_stats[id]['current_revision']
      end
    end
    downstream_boards_changed = false
    changes = {}
    full_set_revision = Digest::MD5.hexdigest(revision_hashes.join('_'))[0, 10]
    if self.settings['full_set_revision'] != full_set_revision
      changes['full_set_revision'] = [self.settings['full_set_revision'], full_set_revision]
      #self.settings['full_set_revision'] = full_set_revision
      downstream_boards_changed = true
      self.schedule_update_button_set
    end
    downstream_buttons_changed = false
    if self.settings['total_downstream_buttons'] != total_buttons
      changes['total_downstream_buttons'] = [self.settings['total_downstream_buttons'], total_buttons]
      #self.settings['total_downstream_buttons'] = total_buttons
      downstream_buttons_changed = true
    end
    if self.settings['unlinked_downstream_buttons'] != unlinked_buttons
      changes['unlinked_downstream_buttons'] = [self.settings['unlinked_downstream_buttons'], unlinked_buttons]
      #self.settings['unlinked_downstream_buttons'] = unlinked_buttons
      downstream_buttons_changed = true
    end
    changes['downstream_board_ids'] = [self.settings['downstream_board_ids'], downs]
    #self.settings['downstream_board_ids'] = downs

    # step 3: notify upstream if there was a change
    Rails.logger.info('saving if changed')
    if changed || downstream_buttons_changed || downstream_boards_changed
      Rails.logger.info('saving because changed') if changed
      Rails.logger.info('saving because buttons changed') if buttons_changed
      Rails.logger.info('saving because downstream buttons changed') if downstream_buttons_changed
      Rails.logger.info('saving because downstream boards changed') if downstream_boards_changed
      @track_downstream_boards = false
      board = Board.find_by_global_id(self.global_id).reload
      changes.each do |key, vals|
        pre, post = vals
        next if pre.to_json == post.to_json
        if board.settings[key] != pre
          Rails.logger.info("bad save, clobbering value for #{key}")
        end
        board.settings[key] = post
        self.settings[key] = post
      end
      updates = {}
      changes.each{|k, vals| updates[k] = vals[1] }
      updates['last_tracked'] = Time.now.to_i
      board.update_setting(updates, nil, :save_without_post_processing)
      board.complete_stream_checks(already_visited_ids, trigger_stamp)
    end
    
    # step 4: update any authors whose list of visible/editable private boards may have changed
    Rails.logger.info('scheduling downstream update')
    if !@skip_update_available_boards
      self.schedule_update_available_boards('downstream')
    end
    @skip_update_available_boards = false
    
    Rails.logger.info('done tracking!')
    true
  end
  
  def schedule_update_button_set
    return true if self.class.add_lumped_trigger({'type' => 'update_button_set', 'id' => self.global_id})
    BoardDownstreamButtonSet.schedule_once(:update_for, self.global_id)
  end
  
  def schedule_update_available_boards(breadth='all', frd=false)
    return true if self.class.add_lumped_trigger({'type' => 'update_available_boards', 'id' => self.global_id, 'breadth' => breadth})
    if !frd
      self.schedule_once(:schedule_update_available_boards, breadth, true)
      return true
    end
    ids = []
    if breadth == 'all'
      ids = self.share_ids
    elsif breadth == 'downstream'
      ids = self.downstream_share_ids
    elsif breadth == 'author'
      ids = self.author_ids
    end
    User.find_all_by_global_id(ids).each do |user|
      user.schedule_once(:update_available_boards)
    end
  end
    
  def complete_stream_checks(notify_upstream_with_visited_ids, trigger_stamp)
    # TODO: as-is this won't unlink from boards when a linked button is removed or modified
    # TODO: this is way too eager
    # Step 1: reach in and add to immediately_upstream_board_ids without triggering any background processes
    downs = Board.find_all_by_global_id(self.settings['immediately_downstream_board_ids'] || [])
    downs.each do |board|
      if board && (!board.settings['immediately_upstream_board_ids'] || !board.settings['immediately_upstream_board_ids'].include?(self.global_id))
        board.add_upstream_board_id!(self.global_id)
      end
    end
    # Step 2: trigger background heavy update for all immediately-upstream boards
    if notify_upstream_with_visited_ids
      ups = Board.find_all_by_global_id(self.settings['immediately_upstream_board_ids'] || [])
      ups.each do |board|
        if board && !notify_upstream_with_visited_ids.include?(board.global_id)
          if trigger_stamp && board.settings['last_tracked'] && board.settings['last_tracked'] > trigger_stamp
            # if the board has been updated more recently than the current tracking sequence started, then
            # it is already up-to-date as far as this sequence is concerned, and doesn't need
            # to be re-scheduled
          else
            board.schedule_once(:track_downstream_boards!, notify_upstream_with_visited_ids, trigger_stamp)
          end
        end
      end
    end
  end
  
  def add_upstream_board_id!(id)
    self.reload
    self.settings ||= {}
    self.settings['immediately_upstream_board_ids'] ||= []
    self.settings['immediately_upstream_board_ids'] << id
    self.settings['immediately_upstream_board_ids'] = self.settings['immediately_upstream_board_ids'].uniq.sort
    self.update_setting('immediately_upstream_board_ids', self.settings['immediately_upstream_board_ids'], :save!)
    BoardDownstreamButtonSet.schedule_once(:update_for, self.global_id)
  end
  
  def update_any_upstream
    self.any_upstream = (self.settings['immediately_upstream_board_ids'] || []).length > 0
    self.save_without_post_processing
  end
  
  def touch_downstreams(already_visited_ids=[])
    ids = [self.global_id] + ((self.settings || {})['downstream_board_ids'] || [])
    ids -= already_visited_ids
    # TODO: sharding
    db_ids = self.class.local_ids(ids)
    Board.where(:id => db_ids).update_all(:updated_at => Time.now)
  end
  
  def schedule_downstream_checks
    if @track_downstream_boards || @buttons_affecting_upstream_changed
      self.schedule(:track_downstream_boards!, [], @buttons_affecting_upstream_changed, Time.now.to_i)
      @buttons_affecting_upstream_changed = nil
      @track_downstream_boards = nil
    end
  end
  
  def update_immediately_downstream_board_ids
    downs = get_immediately_downstream_board_ids
    if self.settings['immediately_downstream_board_ids'] != downs || @button_links_changed
      @track_downstream_boards = true
      @buttons_affecting_upstream_changed = @buttons_changed
      self.settings['immediately_downstream_board_ids'] = downs
    elsif @buttons_changed
      @buttons_affecting_upstream_changed = @buttons_changed
    end
  end
  
  def get_immediately_downstream_board_ids
    downs = []
    (self.settings['buttons'] || []).each do |button|
      if button['load_board'] && button['load_board']['id']
        downs << button['load_board']['id']
      end
    end
    downs = downs.uniq.sort
  end
  

  module ClassMethods
    def lump_triggers
      @@lumped_triggers ||= []
    end
  
    def add_lumped_trigger(trigger)
      @@lumped_triggers ||= nil
      return false unless @@lumped_triggers
      @@lumped_triggers << trigger
      true
    end
  
    def process_lumped_triggers(triggers=nil)
      # TODO: this should go away eventually. Right now if somebody updated
      # board that's linked to, say, 300 other boards, then all those boards
      # needs to have their button_set updated, and available_boards for their
      # users. If you schedule those all out, it would be 600 jobs to 
      # munge through all at once. With enough workers I guess that'd be no
      # big deal, but right now we don't have enough, so those get run
      # in a single long-running job instead.
      @@lumped_triggers ||= nil
      if !triggers && @@lumped_triggers
        if @@lumped_triggers.length > 0
          Worker.schedule_for(:slow, Board, :perform_action, {
            'method' => 'process_lumped_triggers',
            'arguments' => [@@lumped_triggers]
          })
        end
        @@lumped_triggers = nil
      end
      if triggers
        triggers.each do |trigger|
          if trigger['type'] == 'update_button_set' && trigger['id']
            Worker.schedule_for(:slow, BoardDownstreamButtonSet, :perform_action, {
              'method' => 'update_for',
              'arguments' => [trigger['id']]
            })
#            BoardDownstreamButtonSet.update_for(trigger['id'])
          elsif trigger['type'] == 'update_available_boards' && trigger['id']
            user = User.find_by_path(trigger['id'])
            if user
#              user.schedule_update_available_boards(trigger['breadth'], true)
              Worker.schedule_for(:slow, User, :perform_action, {
                'id' => user.id,
                'method' => 'schedule_update_available_boards',
                'arguments' => [trigger['breadth'], true]
              })
            end
          end
        end
      end
    end
  end
  
  included do
    after_create :schedule_update_available_boards
    after_destroy :schedule_update_available_boards
  end
end