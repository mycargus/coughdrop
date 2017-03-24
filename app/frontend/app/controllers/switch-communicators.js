import Ember from 'ember';
import modal from '../utils/modal';
import app_state from '../utils/app_state';

export default modal.ModalController.extend({
  opening: function() {
    this.set('model.jump_home', true);
    this.set('model.keep_as_self', false);
    this.set('has_supervisees', app_state.get('sessionUser.supervisees.length') > 0);
    this.set('currently_selected_id', null);
  },
  self_currently_selected: function() {
    return app_state.get('currentUser.id') && app_state.get('currentUser.id') == app_state.get('sessionUser.id');
  }.property('app_state.currentUser.id'),
  select_on_change: function() {
    if(this.get('currently_selected_id')) {
      this.send('select', this.get('currently_selected_id'));
    }
  }.observes('currently_selected_id'),
  actions: {
    select: function(board_for_user_id) {
      var jump_home = this.get('model.jump_home');
      var keep_as_self = this.get('model.keep_as_self');
      modal.close();
      app_state.set_speak_mode_user(board_for_user_id, jump_home, keep_as_self);
    }
  }
});
