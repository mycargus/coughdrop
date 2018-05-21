import Ember from 'ember';
import Controller from '@ember/controller';

export default Controller.extend({
  actions: {
    board_selection_error: function() {
      this.set('advanced', true);
    }
  }
});
