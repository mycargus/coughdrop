import Ember from 'ember';
import modal from '../utils/modal';
import CoughDrop from '../app';
import app_state from '../utils/app_state';
import i18n from '../utils/i18n';
import editManager from '../utils/edit_manager';
import { htmlSafe } from '@ember/string';

export default modal.ModalController.extend({
  opening: function() {
    if(this.get('model.badge.id') && !this.get('model.badge.completion_settings')) {
      this.get('model.badge').reload();
    }
    var list = [];
    for(var idx = 0; idx < 80; idx++) {
      list.push({
        style: htmlSafe("top: " + (Math.random() * 200) + "px; left: " + (Math.random() *100) + "%;"),
      });
    }
    this.set('confettis', list);
  },
  actions: {
  }
});
