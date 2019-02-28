import Ember from 'ember';
import modal from '../../utils/modal';
import stashes from '../../utils/_stashes';
import persistence from '../../utils/persistence';
import app_state from '../../utils/app_state';
import i18n from '../../utils/i18n';
import { set as emberSet } from '@ember/object';

export default modal.ModalController.extend({
  opening: function() {
    this.set('working_vocalization', stashes.get('working_vocalization'));
    var voc = stashes.get('working_vocalization') || [];
    this.set('working_sentence', voc.map(function(v) { return v.label; }).join(' '));
    this.set('current', null);
    this.set('app_state', app_state);
    var user = app_state.get('referenced_user');
    if(user && user.get('unread_alerts')) {
      user.set('last_alert_access', (new Date()).getTime() / 1000);
      user.save().then(null, function() { });
    }
    this.update_list();
  },
  update_list: function() {
    var _this = this;
    if(!_this.get('status.ready')) {
      _this.set('status', {loading: true});
    }
    persistence.fetch_inbox(app_state.get('referenced_user')).then(function(res) {
      _this.set('alerts', res.alert);
      _this.set('status', {ready: true});
    }, function(err) {
      _this.set('status', {error: true});
    });
  }.observes('app_state.referenced_user'),
  actions: {
    clear: function(which) {
      // TODO: log the cleared mark and push_logs
      if(which == 'all') {

      } else {

      }
    },
    view: function(alert) {
      if(alert.note) {
        this.set('current', alert);
        emberSet(alert, 'unread', false);
        // TODO: log the unread mark and push_logs
      }
    },
    back: function() {
      this.set('current', null);
    },
    reply: function() {
      app_state.set('reply_note', this.get('current'));
      modal.close();
      modal.notice(i18n.t('compose_and_return_to_reply', "Compose your message and go back to the Alerts view to send your message"), true);
      // close modal, but set a flag somewhere that says you're in
      // reply mode, and change the speak-menu button to Send Reply
      // instead of Alerts
    },
    compose: function() {
      if(stashes.get('working_vocalization.length')) {
        if(app_state.get('reply_note')) {
          var user = this.get('reply_note.author');
          if(user) {
            user.user_name = user.user_name || user.name;
            user.avatar_url = user.avatar_url || user.image_url;
            modal.open('confirm-notify-user', {user: user, reply_id: app_state.get('reply_note.id'), raw: stashes.get('working_vocalization'), sentence: this.get('working_sentence'), utterance: null});
          }
        } else {
          modal.open('share-utterance', {utterance: stashes.get('working_vocalization')});
        }
      }
    }
  }
});
