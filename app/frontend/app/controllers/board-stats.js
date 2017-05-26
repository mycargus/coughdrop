import Ember from 'ember';
import persistence from '../utils/persistence';
import app_state from '../utils/app_state';
import modal from '../utils/modal';

export default modal.ModalController.extend({
  opening: function() {
    this.set('model', this.get('model.board'));
    this.load_charts();
  },
  using_user_names: function() {
    return (this.get('model.using_user_names') || []).join(', ');
  }.property('model.using_user_names'),
  load_charts: function() {
    var _this = this;
    _this.set('stats', null);
    if(persistence.get('online') && app_state.get('currentUser')) {
      persistence.ajax('/api/v1/boards/' + _this.get('model.key') + '/stats', {type: 'GET'}).then(function(data) {
        _this.set('stats', data);
      }, function() {
        _this.set('stats', {error: true});
      });
    }
  }
});
