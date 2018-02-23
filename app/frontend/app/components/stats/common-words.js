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
      return htmlSafe('height: 400px; overflow: auto; padding-top: 23px; border-left: 1px solid #eee;');
    } else {
      return htmlSafe('height: 400px; overflow: auto; padding-top: 23px;');
    }
  }.property('right_side'),
  actions: {
    word_cloud: function() {
      this.sendAction('word_cloud');
    },
    word_data: function(word) {
      this.sendAction('word_data', word);
    },
  }
});
