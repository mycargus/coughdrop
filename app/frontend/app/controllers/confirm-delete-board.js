import Ember from 'ember';
import modal from '../utils/modal';
import RSVP from 'rsvp';

export default modal.ModalController.extend({
  opening: function() {
    if(this.get('model.board')) {
      this.get('model.board').reload();
    }
    this.set('delete_downstream', false);
  },
  using_user_names: function() {
    return (this.get('model.board.using_user_names') || []).join(', ');
  }.property('model.board.using_user_names'),
  actions: {
    deleteBoard: function(decision) {
      var _this = this;
      var board = this.get('model.board');
      board.deleteRecord();
      _this.set('model.deleting', true);
      var load_promises = [];
      var other_boards = [];
      if(this.get('delete_downstream')) {
        board.get('downstream_board_ids').forEach(function(id) {
          load_promises.push(_this.store.findRecord('board', id).then(function(board) {
            other_boards.push(board);
          }));
        });
      }
      var save = board.save();

      var wait_for_loads = save.then(function() {
        return RSVP.all_wait(load_promises);
      });

      var delete_others = wait_for_loads.then(function() {
        var delete_promises = [];
        other_boards.forEach(function(b) {
          if(b.get('user_name') == board.get('user_name')) {
            b.deleteRecord();
            delete_promises.push(b.save());
          }
        });
        return RSVP.all_wait(delete_promises);
      });

      delete_others.then(function() {
        if(_this.get('model.redirect')) {
          _this.transitionToRoute('index');
        }
        modal.close();
      }, function() {
        _this.set('model.deleting', false);
        _this.set('model.error', true);
      });
    }
  }
});
