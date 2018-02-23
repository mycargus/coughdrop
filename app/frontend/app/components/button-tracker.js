import Ember from 'ember';
import Component from '@ember/component';
import buttonTracker from '../utils/raw_events';

export default Component.extend({
  didInsertElement: function() {
    buttonTracker.setup();
  }
});
