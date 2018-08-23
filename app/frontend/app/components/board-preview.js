import Ember from 'ember';
import Component from '@ember/component';
import CoughDrop from '../app';
import modal from '../utils/modal';
import app_state from '../utils/app_state';
import persistence from '../utils/persistence';

export default Component.extend({
  willInsertElement: function() {
    this.set('include_canvas', window.outerWidth > 800);
    this.set('model', {loading: true});
    var _this = this;
    if(_this.get('key')) {
      CoughDrop.store.findRecord('board', _this.get('key')).then(function(board) {
        if(!board.get('permissions')) {
          board.reload(false).then(function(board) {
            _this.set('model', board);
          });
        } else {
          _this.set('model', board);
        }
      }, function(err) {
        _this.set('model', {error: true});
      });
    }
  },
  select_option: function() {
    return this.get('option') == 'select';
  }.property('option'),
  actions: {
    select: function() {
      this.sendAction();
    },
    close: function() {
      modal.close_board_preview();
    },
    visit: function() {
      app_state.controller.transitionToRoute('board', this.get('model.key'));
    }
  }
});
