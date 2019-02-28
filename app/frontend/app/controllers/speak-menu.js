import Ember from 'ember';
import { later as runLater } from '@ember/runloop';
import $ from 'jquery';
import modal from '../utils/modal';
import stashes from '../utils/_stashes';
import app_state from '../utils/app_state';
import utterance from '../utils/utterance';
import speecher from '../utils/speecher';
import { set as emberSet } from '@ember/object';
import CoughDrop from '../app';

export default modal.ModalController.extend({
  opening: function() {
    var utterances = stashes.get('remembered_vocalizations') || [];
    if(app_state.get('currentUser')) {
      utterances = utterances.filter(function(u) { return u.stash; }).slice(0, 2);
      (app_state.get('currentUser.vocalizations') || []).forEach(function(u) {
        utterances.push({
          sentence: u.list.map(function(v) { return v.label; }).join(" "),
          vocalizations: u.list,
          stash: false
        });
      });
    }
    this.set('model', {});
    this.set('rememberedUtterances', utterances.slice(0, 7));
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
      modal.close(true);
      if(button == 'remember') {
        app_state.save_phrase(stashes.get('working_vocalization'));
      } else if(button == 'share') {
        if(stashes.get('working_vocalization.length')) {
          modal.open('share-utterance', {utterance: stashes.get('working_vocalization')});
        }
      } else if(button == 'sayLouder') {
        app_state.say_louder();
      } else {
        if(button.stash) {
          utterance.set('rawButtonList', button.vocalizations);
          utterance.set('list_vocalized', false);
          var list = (stashes.get('remembered_vocalizations') || []).filter(function(v) { return !v.stash || v.sentence != button.sentence; });
          stashes.persist('remembered_vocalizations', list);
        } else {
          app_state.set_and_say_buttons(button.vocalizations);
        }
      }
    },
    reply_note: function() {
      if(app_state.get('reply_note')) {
        var user = app_state.get('reply_note.author');
        if(user) {
          emberSet(user, 'user_name', user.user_name || user.name);
          emberSet(user, 'avatar_url', user.avatar_url || user.image_url);
          var voc = stashes.get('working_vocalization') || [];
          var sentence = voc.map(function(v) { return v.label; }).join(' ');
          modal.open('confirm-notify-user', {user: user, reply_id: app_state.get('reply_note.id'), raw: stashes.get('working_vocalization'), sentence: sentence, utterance: null});
        }
      }
    },
    button_event: function(event, button) {
      if(event == 'speakMenuSelect') {
        var click = function() {
          if(app_state.get('currentUser.preferences.click_buttons') && app_state.get('speak_mode')) {
            speecher.click();
          }
        };
        modal.close(true);
        if(button == 'menu_share_button') {
          modal.open('share-utterance', {utterance: stashes.get('working_vocalization')});
          click();
        } else if(button == 'menu_repeat_button') {
          app_state.say_louder();
          // right for louder, left for quieter, down for big target, up for text box
        } else if(button == 'menu_hold_thought_button') {
          stashes.remember({stash: true});
          utterance.clear();
          click();
        } else if(button == 'menu_phrases_button') {
          modal.open('modals/phrases', {inactivity_timeout: true});
          click();
        } else if(button == 'menu_inbox_button') {
          modal.open('modals/inbox', {inactivity_timeout: true});
          click();
        } else if(button == 'menu_repair_button') {
          modal.open('modals/repairs', {inactivity_timeout: true});
          click();
        } else {
          console.error("unrecognized button", button);
        }
      }
    },
    close: function() {
      modal.set('speak_menu_last_closed', Date.now());
      modal.close();
    }
  },
});
