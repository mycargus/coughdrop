import modal from '../../utils/modal';
import i18n from '../../utils/i18n';
import persistence from '../../utils/persistence';
import session from '../../utils/session';
import { later as runLater } from '@ember/runloop';

export default modal.ModalController.extend({
  actions: {
    confirm: function() {
      if(this.get('confirmed') == 'confirmed' || this.get('model.user_name') || this.get('model.unit_user_name')) {
        modal.close({confirmed: true});
      }
    }
  }
});
