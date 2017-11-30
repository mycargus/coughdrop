import Ember from 'ember';
import CoughDrop from '../app';
import app_state from '../utils/app_state';
import contentGrabbers from '../utils/content_grabbers';
import modal from '../utils/modal';

export default modal.ModalController.extend({
  opening: function() {
    this.set('status', null);
  },
  actions: {
    close: function() {
      modal.close(false);
    },
    save: function() {
      var _this = this;
      var org = _this.get('model.org');
      _this.set('status', {saving: true});
      org.save().then(function() {
        modal.close({updated: true});
        _this.set('status', null);
      }, function() {
        _this.set('status', {error: true});
      });
    }
  }
});
