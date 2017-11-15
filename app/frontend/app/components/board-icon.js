import Ember from 'ember';
import CoughDrop from '../app';
import app_state from '../utils/app_state';
import modal from '../utils/modal';

export default Ember.Component.extend({
  willInsertElement: function() {
    this.set_board_record();
  },
  set_board_record: function() {
    var board = this.get('board');
    if(board.children) {
      this.set('children', board.children);
      board = board.board;
    }
    if(!board.reload && board.key) {
      var _this = this;
      CoughDrop.store.findRecord('board', board.key).then(function(b) {
        _this.set('board_record', b);
      }, function() { });
    } else {
      this.set('board_record', board);
    }
  }.observes('board', 'board.key'),
  display_class: function() {
    var e = this.element;
    var bounds = e.getBoundingClientRect();
    var res ='btn simple_board_icon btn-default';
    if(bounds.width < 120) {
      res = res + ' tiny';
    } else if(bounds.width < 150) {
      res = res + ' short';
    } else if(bounds.width < 180) {
      res = res + ' medium';
    }
    if(this.get('children')) {
      res = res + ' folder';
    }
    return Ember.String.htmlSafe(res);
  }.property('children'),
  actions: {
    board_preview: function(board) {
      var _this = this;
      board.preview_option = null;
      modal.board_preview(board, function() {
        _this.send('pick_board', board);
      });
    },
    pick_board: function(board) {
      var _this = this;
      if(this.get('children')) {
        _this.sendAction('action', this.get('board'));
      } else if(this.get('option') == 'select') {
        board.preview_option = 'select';
        modal.board_preview(board, function() {
          _this.sendAction('action', board);
        });
      } else {
        app_state.home_in_speak_mode({force_board_state: {key: board.get('key'), id: board.get('id')}});
      }
    }
  }
});
