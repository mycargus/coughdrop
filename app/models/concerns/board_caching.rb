module BoardCaching
  extend ActiveSupport::Concern
  
  # when to update this list for a user:
  # - board is shared/unshared with the user
  # - supervisee is added/removed
  # - authored/co-authored board is created, links modified, or changed to public/private
  # - board downstream of a authored/co-authored board is created, links modified, or changed to public/private
  # - board downstream of a downstream-shared board is created, links modified, or changed to public/private
  
  # explicitly-shared boards are viewable
  # the author's supervisors can view the author's boards
  # the user (and co-authors) should have edit and sharing access
  # the user and any of their editing supervisors should have edit access
  # the user should have edit and sharing access if a parent board is edit-shared including downstream with them
  # the user should have view access if the board is shared with any of their supervisees

  def update_available_boards
    # find all private boards authored by this user
    # TODO: sharding
    authored = Board.where(:public => false, :user_id => self.id).select('id').map(&:global_id)
    # find all private boards shared with this user
    # find all private boards where this user is a co-author
    # find all private boards downstream of boards shared with this user
    # find all private boards downstream of boards edit-shared with this user
    self.clear_cached("all_shared_board_ids/true")
    self.clear_cached("all_shared_board_ids/false")
    view_shared = Board.all_shared_board_ids_for(self, false)
    edit_shared = Board.all_shared_board_ids_for(self, true)

    # find all private boards available to this user's supervisees
    # find all private boards downstream of boards edit-shared with this user's supervisees
    supervisee_authored = []
    supervisee_view_shared = []
    supervisee_edit_shared = []
    self.supervisees.select{|s| self.edit_permission_for?(s) }.each do |sup|
      supervisee_view_shared += sup.private_viewable_board_ids
      supervisee_edit_shared += sup.private_editable_board_ids
#       # TODO: sharding
#       supervisee_authored += Board.where(:public => false, :user_id => sup.id).select('id').map(&:global_id)
#       supervisee_view_shared += Board.all_shared_board_ids_for(sup, false)
#       supervisee_edit_shared += Board.all_shared_board_ids_for(sup, true)
    end
    # generate a list of all private boards this user can edit/delete/share
    edit_ids = (authored + edit_shared + supervisee_authored + supervisee_edit_shared).uniq
    # generate a list of all private boards this user can view
    view_ids = (edit_ids + view_shared + supervisee_view_shared).uniq
    # TODO: sharding
    view_ids = Board.where(:public => false, :id => self.class.local_ids(view_ids)).select('id').map(&:global_id).sort
    edit_ids = Board.where(:id => self.class.local_ids(edit_ids)).select('id').map(&:global_id).sort
    self.settings ||= {}
    self.settings['available_private_board_ids'] ||= {
      'view' => [],
      'edit' => []
    }
    ab_json = self.settings['available_private_board_ids'].to_json
    self.settings['available_private_board_ids']['view'] = view_ids
    self.settings['available_private_board_ids']['edit'] = edit_ids
    # save those lists
    @do_track_boards = false
    self.assert_current_record!
    self.save
    # if the lists changed, schedule this same update for all users
    # who would have been affected by a change (supervisors)
    if ab_json != self.settings['available_private_board_ids'].to_json
      self.supervisors.each do |sup|
        sup.schedule_once(:update_available_boards)
      end
    end
  rescue ActiveRecord::StaleObjectError
    self.schedule_once(:update_available_boards)
  end
  
  def private_viewable_board_ids
    self.settings ||= {}
    ((self.settings['available_private_board_ids'] || {})['view'] || [])
  end
  
  def private_editable_board_ids
    # kind of a lie, since it includes shared public boards as well
    self.settings ||= {}
    ((self.settings['available_private_board_ids'] || {})['edit'] || [])
  end
  
  def can_view?(board)
    private_viewable_board_ids.include?(board.global_id)
  end
  
  def can_edit?(board)
    private_editable_board_ids.include?(board.global_id)
  end
end

