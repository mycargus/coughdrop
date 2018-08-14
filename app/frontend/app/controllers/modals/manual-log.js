import Ember from 'ember';
import modal from '../../utils/modal';

export default modal.ModalController.extend({
  actions: {
    submit: function() {
      var text = this.get('words');
      var date = window.moment(this.get('date') + ' ' + this.get('time'))._d;
      modal.close({
        words: text,
        date: date
      });
    }
  }
});
