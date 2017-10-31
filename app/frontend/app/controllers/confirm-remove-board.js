import Ember from 'ember';
import modal from '../utils/modal';
import i18n from '../utils/i18n';
import persistence from '../utils/persistence';

export default modal.ModalController.extend({
  opening: function() {
    this.set('loading', false);
    this.set('error', false);
  },
  delete_action: function() {
    return this.get('model.action') == 'delete';
  }.property('model.action'),
  unlink_action: function() {
    return this.get('model.action') == 'unlink';
  }.property('model.action'),
  unstar_action: function() {
    return this.get('model.action') == 'unstar';
  }.property('model.action'),
  actions: {
    remove: function() {
      var board = this.get('model.board');
      var user = this.get('model.user');
      var _this = this;
      _this.set('loading', true);
      _this.set('error', false);
      persistence.ajax('/api/v1/boards/unlink', {type: 'POST', data: {board_id: board.get('id'), user_id: user.get('id'), type: this.get('model.action')}}).then(function(res) {
        _this.set('loading', false);
        _this.set('error', false);
        board.set('removed', true);

        modal.close();
      }, function() {
        _this.set('loading', false);
        _this.set('error', true);
      });
    }
  }
});

