import Ember from 'ember';
import Controller from '@ember/controller';
import CoughDrop from '../../app';
import Utils from '../../utils/misc';

export default Controller.extend({
  load_results: function() {
    var _this = this;
    _this.set('loading', true);
    _this.set('error', false);
    CoughDrop.store.query('boardversion', {board_id: this.get('key')}).then(function(res) {
      _this.set('loading', false);
      _this.set('versions', res);
    }, function(err) {
      _this.set('loading', false);
      _this.set('error', true);
    });
  },
  possible_upstream_boards: function() {
    var res = [];
    (this.get('versions') || []).forEach(function(v) {
      (v.get('immediately_upstream_boards') || []).forEach(function(b) {
        res.push(b);
      });
    });
    res = Utils.uniq(res, function(b) { return b.id; });
    return res;
  }.property('versions'),
  maybe_more: function() {
    return this.get('versions.length') >= 25;
  }.property('versions')
});
