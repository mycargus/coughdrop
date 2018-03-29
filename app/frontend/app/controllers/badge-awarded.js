import Ember from 'ember';
import modal from '../utils/modal';
import CoughDrop from '../app';
import app_state from '../utils/app_state';
import i18n from '../utils/i18n';
import editManager from '../utils/edit_manager';
import { htmlSafe } from '@ember/string';

export default modal.ModalController.extend({
  opening: function() {
    var _this = this;
    if(_this.get('model.badge.id') && !_this.get('model.badge.completion_settings')) {
      if(!_this.get('model.badge').reload) {
        _this.set('model.badge.loading', true);
        CoughDrop.store.findRecord('badge', _this.get('model.badge.id')).then(function(b) {
          _this.set('model.badge', b);
        }, function(err) {
          _this.set('model.badge.error', true);
        });
      } else {
        _this.get('model.badge').reload();
      }
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
