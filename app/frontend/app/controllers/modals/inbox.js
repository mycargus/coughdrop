import Ember from 'ember';
import modal from '../../utils/modal';
import stashes from '../../utils/_stashes';
import app_state from '../../utils/app_state';
import utterance from '../../utils/utterance';
import CoughDrop from '../../app';

export default modal.ModalController.extend({
  opening: function() {
    this.set('working_vocalization', stashes.get('working_vocalization'));
    this.update_list();
  },
  update_list: function() {
  }.observes('app_state'),
  actions: {
    clear: function() {

    },
    reply: function() {
      // close modal, but set a flag somewhere that says you're in
      // reply mode, and change the speak-menu button to Send Reply
      // instead of Alerts
    },
    compose: function() {
      // share-utterance
    }
  }
});
