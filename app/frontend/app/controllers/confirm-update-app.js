import Ember from 'ember';
import modal from '../utils/modal';

export default modal.ModalController.extend({
  version: function() {
    return (window.CoughDrop && window.CoughDrop.update_version) || 'unknown';
  }.property(),
  actions: {
    restart: function() {
      if(window.CoughDrop && window.CoughDrop.install_update) {
        window.CoughDrop.install_update();
      } else {
        this.set('error', true);
      }
    }
  }
});
