import Ember from 'ember';
import Component from '@ember/component';

export default Component.extend({
  tagName: 'input',
  type: 'text',
  attributeBindings: ['placeholder'],
  didInsertElement: function() {
    this.update_placeholder();
  },
  update_placeholder: function() {
    if(this.$()) {
      if(this.get('value')) {
        this.$().attr('placeholder', '##');
        this.$().attr('value', this.get('value'));
      } else {
        this.$().attr('placeholder', '');
      }
    }
  }.observes('value'),
  keyDown: function(event) {
    if(this.get('value') == '9' && event.keyCode == 9) {
      // double-tab to escape text entry lockage
      return;
    }
    this.$().val(event.keyCode);
    event.preventDefault();
    this.set('value', event.keyCode);
  }
});
