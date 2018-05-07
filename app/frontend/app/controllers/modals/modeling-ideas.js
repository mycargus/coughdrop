import modal from '../../utils/modal';
import app_state from '../../utils/app_state';

export default modal.ModalController.extend({
  opening: function() {
    var users = this.get('model.users');
  }
});
