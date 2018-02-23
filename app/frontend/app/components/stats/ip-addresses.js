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
      return htmlSafe('border-left: 1px solid #eee;');
    } else {
      return htmlSafe('');
    }
  }.property('right_side'),
  inner_elem_style: function() {
    if(this.get('side_by_side')) {
      return htmlSafe('padding-top: 24px; height: 200px; overflow: auto;');
    } else {
      return htmlSafe('padding-top: 24px; max-height: 350px; overflow: auto;');
    }
  }.property('side_by_side'),
  actions: {
    filter: function(ip) {
      this.sendAction('filter', 'location', ip.id);
    }
  }
});
