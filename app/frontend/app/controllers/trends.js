import Ember from 'ember';
import i18n from '../utils/i18n';
import persistence from '../utils/persistence';
import app_state from '../utils/app_state';
import modal from '../utils/modal';

export default Ember.Controller.extend({
  load_trends: function() {
    var _this = this;
    _this.set('trends', {loading: true});
    persistence.ajax('/api/v1/logs/trends', {type: 'GET'}).then(function(res) {
      _this.set('trends', res);
    }, function(err) {
      _this.set('trends', {error: true});
    });
    Ember.run.later(function() {
      _this.set('word_cloud_id', Math.random());
    }, 2000);
  },
  word_cloud_stats: function() {
    var res = Ember.Object.create({
      words_by_frequency: []
    });
    var counts = this.get('trends.word_counts') || {};
    for(var idx in counts) {
      res.get('words_by_frequency').pushObject({text: idx, count: counts[idx]});
    }
    return res;
  }.property('trends.word_counts'),
  home_boards: function() {
    var hash = this.get('trends.home_boards');
    if(hash) {
      var res = [];
      for(var idx in hash) {
        res.push({key: idx, pct: hash[idx]});
      }
      return res.sort(function(a, b) {
        return b.pct - a.pct;
      });
    }
  }.property('trends.home_boards'),
  actions: {
    show_private_info: function() {
      this.set('showing_private_info', true);
    }
  }
});
