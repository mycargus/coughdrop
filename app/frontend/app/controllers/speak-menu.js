import Ember from 'ember';
import { later as runLater } from '@ember/runloop';
import $ from 'jquery';
import modal from '../utils/modal';
import stashes from '../utils/_stashes';
import app_state from '../utils/app_state';
import CoughDrop from '../app';

export default modal.ModalController.extend({
  opening: function() {
    var utterances = stashes.get('remembered_vocalizations');
    this.set('model', {});
    this.set('rememberedUtterances', utterances);
    var height = app_state.get('header_height');
    runLater(function() {
      $("#speak_menu").closest(".modal-dialog").css('top', (height - 40) + 'px');
    }, 100);
  },
  sharing_allowed: function() {
    return (!this.get('app_state.currentUser') && window.user_preferences.any_user.sharing) || this.get('app_state.currentUser.preferences.sharing');
  }.property('app_state.currentUser', 'app_state.currentUser.preferences.sharing'),
  working_vocalization_text: function() {
    var buttons = stashes.get('working_vocalization') || [{label: "no text"}];
    return buttons.map(function(b) { return b.label; }).join(" ");
  }.property('stashes.working_vocalization'),
  actions: {
    selectButton: function(button) {
      if(button == 'remember') {
        stashes.remember();
        modal.close(true);
      } else if(button == 'share') {
        modal.close(true);
        // TODO: browser-style share option
        modal.open('share-utterance', {utterance: stashes.get('working_vocalization')});
      } else if(button == 'sayLouder') {
        modal.close(true);
        app_state.say_louder();
      } else {
        modal.close(true);
        app_state.set_and_say_buttons(button.vocalizations);
      }
    },
    close: function() {
      modal.set('speak_menu_last_closed', Date.now());
      modal.close();
    }
  },
});
