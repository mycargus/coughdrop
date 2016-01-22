import Ember from 'ember';

export default Ember.Component.extend({
  tagName: 'canvas',
  attributeBindings: ['tabindex'],
  didInsertElement: function() {
    this.sendAction('redraw');
  }
});
