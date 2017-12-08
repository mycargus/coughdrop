import modal from '../utils/modal';
import session from '../utils/session';

export default modal.ModalController.extend({
  actions: {
    logout: function() {
      this.set('logging_out', true);
      session.invalidate(true);
    }
  }
});
