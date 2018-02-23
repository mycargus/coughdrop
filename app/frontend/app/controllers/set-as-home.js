import Ember from 'ember';
import { later as runLater } from '@ember/runloop';
import modal from '../utils/modal';
import app_state from '../utils/app_state';
import editManager from '../utils/edit_manager';
import persistence from '../utils/persistence';
import CoughDrop from '../app';

export default modal.ModalController.extend({
  opening: function() {
    this.set('has_supervisees', app_state.get('sessionUser.supervisees.length') > 0);
    this.set('currently_selected_id', null);
    this.set('status', null);
  },
  owned_by_user: function() {
    var board_user_name = this.get('model.board.user_name');
    var user_name = 'nobody';
    var current_id = this.get('currently_selected_id');
    if(current_id == 'self') {
      user_name = app_state.get('sessionUser.user_name');
    } else if(current_id == app_state.get('sessionUser.user_id')) {
      user_name = app_state.get('sessionUser.user_name');
    } else {
      (app_state.get('sessionUser.supervisees') || []).forEach(function(sup) {
        if(sup.id == current_id) {
          user_name = sup.user_name;
        }
      });
    }
    return user_name == board_user_name;
  }.property('currently_selected_id', 'model.board.user_name'),
  multiple_users: function() {
    return !!this.get('has_supervisees');
  }.property('has_supervisees'),
  pending: function() {
    return this.get('status.updating') || this.get('status.copying');
  }.property('status.updating', 'status.copying'),
  actions: {
    copy_as_home: function() {
      var _this = this;
      var for_user_id = this.get('currently_selected_id') || 'self';
      _this.set('status', {copying: true});
      var board = _this.get('model.board');
      CoughDrop.store.findRecord('user', for_user_id).then(function(user) {
        editManager.copy_board(board, 'links_copy_as_home', user, false).then(function() {
          _this.send('done');
        }, function() {
          _this.set('status', {errored: true});
        });
      }, function() {
        _this.set('status', {errored: true});
      });
    },
    done: function() {
      var _this = this;
      _this.set('status', null);
      modal.close();
      if(persistence.get('online')) {
        runLater(function() {
          console.debug('syncing because set as home');
          persistence.sync('self').then(null, function() { });
        }, 1000);
      }
    },
    set_as_home: function(for_user_id) {
      var for_user_id = this.get('currently_selected_id') || 'self';
      var _this = this;
      var board = this.get('model.board');
      _this.set('status', {updating: true});

      CoughDrop.store.findRecord('user', for_user_id).then(function(user) {
        user.set('preferences.home_board', {
          id: board.get('id'),
          key: board.get('key')
        });
        user.save().then(function() {
          _this.send('done');
        }, function() {
          _this.set('status', {errored: true});
        });
      }, function() {
        _this.set('status', {errored: true});
      });
    }
  }
});
