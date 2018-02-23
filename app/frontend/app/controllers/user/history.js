import Ember from 'ember';
import Controller from '@ember/controller';
import CoughDrop from '../../app';
import Utils from '../../utils/misc';

export default Controller.extend({
  load_results: function() {
    var _this = this;
    _this.set('history', {loading: true});
    CoughDrop.store.query('userversion', {user_id: this.get('model.id')}).then(function(res) {
      _this.set('history', res);
    }, function(err) {
      _this.set('history', {error: true});
    });
  },
  maybe_more: function() {
    return this.get('history.length') >= 25;
  }.property('history')
});
