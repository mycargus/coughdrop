import Ember from 'ember';
import modal from '../../utils/modal';
import stashes from '../../utils/_stashes';
import app_state from '../../utils/app_state';
import utterance from '../../utils/utterance';
import CoughDrop from '../../app';

export default modal.ModalController.extend({
  opening: function() {
    var voc = stashes.get('working_vocalization') || [];
    this.set('sentence', voc.map(function(v) { return v.label; }).join(' '));
    this.set('app_state', app_state);
    this.set('stashes', stashes);
    this.update_list();
  },
  update_list: function() {
    var utterances = stashes.get('remembered_vocalizations') || [];
    if(app_state.get('currentUser')) {
      utterances = utterances.filter(function(u) { return u.stash; });
      (app_state.get('currentUser.vocalizations') || []).forEach(function(u) {
        if(u && u.list) {
          utterances.push({
            id: u.id,
            sentence: u.list.map(function(v) { return v.label; }).join(" "),
            vocalizations: u.list,
            stash: false
          });
        }
      });
    }
    this.set('phrases', utterances);
  }.observes('stashes.remembered_vocalizations.length', 'app_state.currentUser.vocalizations', 'app_state.currentUser.vocalizations.@each.id'),
  actions: {
    select: function(button) {
      if(button.stash) {
        utterance.set('rawButtonList', button.vocalizations);
        utterance.set('list_vocalized', false);
        var list = (stashes.get('remembered_vocalizations') || []).filter(function(v) { return !v.stash || v.sentence != button.sentence; });
        stashes.persist('remembered_vocalizations', list);
      } else {
        app_state.set_and_say_buttons(button.vocalizations);
      }
      modal.close();
    },
    remove: function(phrase) {
      app_state.remove_phrase(phrase);
      this.update_list();
    },
    shift: function(phrase, direction) {
      app_state.shift_phrase(phrase, direction);
      this.update_list();
    },
    add: function() {
      var sentence = this.get('sentence');
      if(!sentence) { return; }
      var voc = stashes.get('working_vocalization') || [];
      var working = voc.map(function(v) { return v.label; }).join(' ');
      if(sentence != working) {
        voc = [
          {label: sentence}
        ];
      }
      app_state.save_phrase(voc);
      this.update_list();
      this.set('sentence', null);
    }
  }
});
