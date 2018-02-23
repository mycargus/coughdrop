import Ember from 'ember';
import Component from '@ember/component';
import $ from 'jquery';
import editManager from '../utils/edit_manager';

export default Component.extend({
  tagName: 'input',
  type: 'text',
  attributeBindings: ['placeholder', 'value'],
  change: function() {
    this.set('changed_value', this.get('element').value);
  },
  valueChange: function() {
    var id = $(this.get('element')).closest('.button').attr('data-id');
    var button = editManager.find_button(id);
    if(button && this.get('changed_value') != button.label) {
      editManager.change_button(id, {
        label: this.get('changed_value')
      });
    }
  }.observes('changed_value'),
  focusIn: function(event) {
    var id = $(this.get('element')).closest('.button').attr('data-id');
    editManager.clear_text_edit();
  },
  keyPress: function(event) {
    if(event.keyCode == 13) {
      this.change.call(this);
      var id = $(this.get('element')).closest('.button').attr('data-id');
      editManager.lucky_symbol(id);
    }
  },
  focusOut: function() {
    var id = $(this.get('element')).closest('.button').attr('data-id');
    editManager.lucky_symbol(id);
  }

});
