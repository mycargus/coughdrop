import Ember from 'ember';
import Component from '@ember/component';
import buttonTracker from '../utils/raw_events';
import app_state from '../utils/app_state';
import editManager from '../utils/edit_manager';
import capabilities from '../utils/capabilities';

export default Component.extend({
  tagName: 'span',
  mouseDown: function() {
    this.sendAction('select');
  },
  touchStart: function() {
    this.sendAction('select');
  }
});
