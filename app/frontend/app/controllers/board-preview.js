import Ember from 'ember';
import modal from '../utils/modal';

export default Ember.Controller.extend({
  actions: {
    close: function() {
      modal.close_board_preview();
    },
    select: function() {
      this.send('close');
      if(this.get('model.callback')) {
        this.get('model.callback')();
      }
    }
  }
});
