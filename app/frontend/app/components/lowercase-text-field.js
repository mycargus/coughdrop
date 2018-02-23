import Ember from 'ember';
import Component from '@ember/component';

export default Component.extend({
  tagName: 'input',
  type: 'text',
  autocapitalize: 'off',
  autocorrect: 'off',
  attributeBindings: ['placeholder', 'value', 'autocapitalize', 'autocorrect'],
  change: function() {
    this.set('value', this.get('element').value);
  }
});
