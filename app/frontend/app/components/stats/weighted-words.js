import Ember from 'ember';

export default Ember.Component.extend({
  elem_class: function() {
    if(this.get('side_by_side')) {
      return Ember.String.htmlSafe('col-sm-6');
    } else {
      return Ember.String.htmlSafe('col-sm-4');
    }
  }.property('side_by_side'),
  elem_style: function() {
    if(this.get('right_side')) {
      return Ember.String.htmlSafe('border-left: 1px solid #eee;');
    } else {
      return Ember.String.htmlSafe('');
    }
  }.property('right_side'),
  inner_elem_style: function() {
    if(this.get('side_by_side')) {
      return Ember.String.htmlSafe('margin-top: 30px; height: 150px; overflow-y: scroll;');
    } else {
      return Ember.String.htmlSafe('margin-top: 30px; max-height: 200px; overflow-y: scroll;');
    }
  }.property('side_by_side'),
  actions: {
    word_cloud: function() {
      this.sendAction('word_cloud');
    },
    word_data: function(word) {
      this.sendAction('word_data', word);
    },
  }
});
