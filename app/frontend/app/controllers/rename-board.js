import Ember from 'ember';
import modal from '../utils/modal';
import BoardHierarchy from '../utils/board_hierarchy';
import i18n from '../utils/i18n';
import persistence from '../utils/persistence';

export default modal.ModalController.extend({
  opening: function() {
    this.set('status', null);
  },
  old_key: function() {
    return (this.get('model.board.key') || "").split(/\//)[1];
  }.property('model.board.key'),
  actions: {
    rename: function() {
      if(this.get('old_key') == this.get('old_key_value') && this.get('new_key_value')) {
        var _this = this;
        _this.set('status', {renaming: true});
        var user_name = _this.get('model.board.user_name');
        persistence.ajax('/api/v1/boards/' + _this.get('model.board.id') + '/rename', {
          type: 'POST',
          data: {
            old_key: user_name + "/" + _this.get('old_key_value'),
            new_key: user_name + "/" + _this.get('new_key_value')
          }
        }).then(function(res) {
          modal.close();
          _this.transitionToRoute('board.index', res.key);
          Ember.run.later(function() {
            modal.success(i18n.t('board_successfully_renamed', "Board successfully renamed to %{n}", {n: res.key}));
          }, 200);
        }, function(err) {
          _this.set('status', {error: true});
        });
      }
    },
    nothing: function() {
    }
  }
});
