import Ember from 'ember';
import Component from '@ember/component';
import { htmlSafe } from '@ember/string';

export default Component.extend({
  elem_class: function() {
    if(this.get('side_by_side')) {
      return htmlSafe('col-sm-6');
    } else {
      return htmlSafe('col-sm-4');
    }
  }.property('side_by_side'),
  elem_style: function() {
    if(this.get('right_side')) {
      return htmlSafe('height: 400px; padding-top: 23px; border-left: 1px solid #eee;');
    } else {
      return htmlSafe('height: 400px; padding-top: 23px;');
    }
  }.property('right_side'),
  lost_words: function() {
    if(this.get('usage_stats') && this.get('ref_stats') && this.get('this_before_that')) {
      var percents = [];
      var _this = this;
      this.get('usage_stats.words_by_frequency').forEach(function(word) {
        var pre_percent = word.count / _this.get('usage_stats.total_words');
        var found_word = _this.get('ref_stats.words_by_frequency').find(function(w) { return w.text == word.text; });
        var post_percent = found_word ? (found_word.count / _this.get('ref_stats.total_words')) : 0;
        if(post_percent < pre_percent) {
          var res = {
            text: word.text,
            multiplier: Math.round((pre_percent / post_percent) * 10) / 10.0,
            percent: Math.round((pre_percent / post_percent) * 1000) / 10.0,
            pre: Math.round(pre_percent * 1000) / 10.0,
            post: Math.round(post_percent * 1000) / 10.0
          };
          if(post_percent === 0) {
            res.gone = true;
            res.multiplier = pre_percent * 100 * 10;
          }
          percents.push(res);
        }
      });
      percents = percents.sort(function(a, b) { return b.multiplier - a.multiplier; });
      percents.some = true;
      return percents.slice(0, 10);
    }
    return null;
  }.property('usage_stats', 'ref_stats'),
  gained_words: function() {
    if(this.get('usage_stats') && this.get('ref_stats') && this.get('that_before_this')) {
      var percents = [];
      var _this = this;
      this.get('usage_stats.words_by_frequency').forEach(function(word) {
        var post_percent = word.count / _this.get('usage_stats.total_words');
        var found_word = _this.get('ref_stats.words_by_frequency').find(function(w) { return w.text == word.text; });
        var pre_percent = found_word ? (found_word.count / _this.get('ref_stats.total_words')) : 0;
        if(post_percent > pre_percent) {
          var res = {
            text: word.text,
            multiplier: Math.round((post_percent / pre_percent) * 10) / 10.0,
            percent: Math.round((post_percent / pre_percent) * 1000) / 10.0,
            pre: Math.round(pre_percent * 1000) / 10.0,
            post: Math.round(post_percent * 1000) / 10.0
          };
          if(pre_percent === 0) {
            res['new'] = true;
            res.multiplier = post_percent * 100 * 10;
          }
          percents.push(res);
        }
      });
      percents = percents.sort(function(a, b) { return b.multiplier - a.multiplier; });
      percents.some = true;
      return percents.slice(0, 10);
    }
    return null;
  }.property('usage_stats', 'ref_stats'),
  this_before_that: function() {
    if(this.get('usage_stats') && this.get('ref_stats')) {
      return this.get('usage_stats').comes_before(this.get('ref_stats'));
    }
    return false;
  }.property('usage_stats', 'ref_stats'),
  that_before_this: function() {
    if(this.get('usage_stats') && this.get('ref_stats')) {
      return this.get('ref_stats').comes_before(this.get('usage_stats'));
    }
    return false;
  }.property('usage_stats', 'ref_stats'),
  actions: {
    word_cloud: function() {
      this.sendAction('word_cloud');
    }
  }
});
