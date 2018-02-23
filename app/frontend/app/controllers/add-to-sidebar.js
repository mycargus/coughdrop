import Ember from 'ember';
import { later as runLater } from '@ember/runloop';
import modal from '../utils/modal';
import app_state from '../utils/app_state';
import i18n from '../utils/i18n';
import persistence from '../utils/persistence';
import CoughDrop from '../app';

export default modal.ModalController.extend({
  opening: function() {
    var supervisees = [];
    this.set('has_supervisees', app_state.get('sessionUser.supervisees.length') > 0);
    this.set('loading', false);
    this.set('error', false);
    this.set('currently_selected_id', null);
    if(supervisees.length === 0) {
      this.set('currently_selected_id', 'self');
    }
  },
  user_board: function() {
    var for_user_id = this.get('currently_selected_id');
    this.set('self_currently_selected', for_user_id == 'self');
    if(this.get('model.supervisees')) {
      this.get('model.supervisees').forEach(function(sup) {
        if(for_user_id == sup.id) {
          sup.set('currently_selected', true);
        } else {
          sup.set('currently_selected', false);
        }
      });
    }
  }.observes('currently_selected_id', 'model.supervisees'),
  actions: {
    add: function() {
      var board = this.get('model.board');
      var user_id = this.get('currently_selected_id');
      var _this = this;

      _this.set('loading', true);

      var find_user = CoughDrop.store.findRecord('user', user_id);

      var update_user = find_user.then(function(user) {
        var boards = user.get('preferences.sidebar_boards');
        if(!boards || boards.length === 0) {
          boards = window.user_preferences.any_user.default_sidebar_boards;
        }
        boards.unshift({
          name: board.name,
          key: board.key,
          home_lock: !!board.home_lock,
          image: board.image
        });

        user.set('preferences.sidebar_boards', boards);
        return user.save();
      });

      update_user.then(function(user) {
        _this.set('loading', false);
        if(persistence.get('online')) {
          runLater(function() {
            console.debug('syncing because sidebar updated');
            persistence.sync('self').then(null, function() { });
          }, 1000);
        }
        modal.close('add-to-sidebar');
        modal.success(i18n.t('added_to_sidebar', "Added to the user's sidebar!"));
      }, function() {
        _this.set('loading', false);
        _this.set('error', true);
      });
    }
  }
});
