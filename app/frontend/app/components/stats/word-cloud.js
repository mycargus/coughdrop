import Ember from 'ember';
import Component from '@ember/component';
import CoughDrop from '../../app';
import i18n from '../../utils/i18n';
import { htmlSafe } from '@ember/string';

export default Component.extend({
  didInsertElement: function() {
    this.draw();
  },
  canvas_style: function() {
    var res = 'width: 100%; height: 400px;';
    if(this.get('short')) { res = "width: 100%; height: 300px;"; }
    return htmlSafe(res);
  }.property('short'),
  canvas_height: function() {
    return htmlSafe(this.get('short') ? (768 * 2 / 3) : 768);
  }.property('short'),
  draw: function() {
    var elem = this.get('element').getElementsByClassName('word_cloud')[0];
    if(elem) {
      var list = [];
      var max = 1;
      var _this = this;
      var list1 = (this.get('stats.modeling') ? this.get('stats.modeled_words_by_frequency') : this.get('stats.words_by_frequency')) || [];
      list1.forEach(function(obj) {
        if(!obj.text.match(/^[\+:]/)) {
          max = Math.max(max, obj.count);
          list.push([obj.text, obj.count]);
        }
      });
      if(this.get('ref_stats')) {
        var list2 = (this.get('ref_stats.modeling') ? this.get('ref_stats.modeled_words_by_frequency') : this.get('ref_stats.words_by_frequency')) || [];
        list2.forEach(function(obj) {
          if(!obj.text.match(/^[\+:]/)) {
            max = Math.max(max, obj.count);
          }
        });
      }
      window.WordCloud(elem, {
        list: list,
        gridSize: 16,
        weightFactor: function (size) {
          var res = ((size / max) * 245 * (_this.get('zoom') || 1)) + 5;
          return res;
        }
      });
    }
  }.observes('stats', 'ref_stats', 'zoom', 'word_cloud_id')
});
