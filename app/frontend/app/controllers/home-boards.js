import Ember from 'ember';
import { later as runLater } from '@ember/runloop';
import modal from '../utils/modal';
import i18n from '../utils/i18n';
import Controller from '@ember/controller';

export default Controller.extend({
  actions: {
    show_advanced: function() {
      this.set('advanced', true);
    },
    select_board: function() {
      this.transitionToRoute('index');
      runLater(function() {
        modal.success(i18n.t('board_layout_copying', "Great, we've got just the board for you! CoughDrop is making your own personal copy based on your choices. You can start using it by entering Speak Mode when you're ready."), true, true);
      }, 100);
    }
  }
});
