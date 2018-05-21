import Ember from 'ember';
import Controller from '@ember/controller';

export default Controller.extend({
  actions: {
    show_advanced: function() {
      this.set('advanced', true);
    },
    select_board: function() {
      this.transitionToRoute('index');
    }
  }
});
