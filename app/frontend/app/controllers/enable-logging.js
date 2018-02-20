import Ember from 'ember';
import modal from '../utils/modal';
import persistence from '../utils/persistence';
import app_state from '../utils/app_state';
import i18n from '../utils/i18n';

export default modal.ModalController.extend({
  opening: function() {
    this.set('research', false);
    this.set('model.user.preferences.allow_log_reports', false);
  },
  closing: function() {
    if(this.get('research')) {
      this.set('model.user.preferences.allow_log_reports', true);
    } else {
      this.set('model.user.preferences.allow_log_reports', false);
    }
    if(this.get('model.save')) {
      this.get('model.user').save();
    }
  },
  actions: {
  }
});
