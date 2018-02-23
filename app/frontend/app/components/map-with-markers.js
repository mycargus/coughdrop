import Ember from 'ember';
import Component from '@ember/component';
import $ from 'jquery';

export default Component.extend({
  click: function(event) {
    if(event.target.tagName == 'A' && event.target.className == 'ember_link') {
      event.preventDefault();
      this.sendAction('action', $(event.target).data());
    }
  }
});
