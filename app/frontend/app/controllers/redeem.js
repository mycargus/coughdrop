import Ember from 'ember';
import Controller from '@ember/controller';

export default Controller.extend({
  actions: {
    check_code: function() {
      if(this.get('redeem_code')) {
        this.transitionToRoute('redeem_with_code', this.get('redeem_code'));
      }
    }
  }
});
