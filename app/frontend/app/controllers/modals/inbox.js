import Ember from 'ember';
import modal from '../../utils/modal';
import stashes from '../../utils/_stashes';
import persistence from '../../utils/persistence';
import app_state from '../../utils/app_state';
import i18n from '../../utils/i18n';
import { set as emberSet, get as emberGet } from '@ember/object';

export default modal.ModalController.extend({
  opening: function() {
    this.set('working_vocalization', stashes.get('working_vocalization'));
    var voc = stashes.get('working_vocalization') || [];
    this.set('working_sentence', voc.map(function(v) { return v.label; }).join(' '));
    this.set('current', null);
    this.set('alerts', null);
    this.set('fetched_inbox', null);
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
      _this.set('fetched_inbox', res);
      _this.set('status', {ready: true});
    }, function(err) {
      _this.set('status', {error: true});
    });
  }.observes('app_state.referenced_user'),
  update_inbox: function(updates) {
    stashes.push_log();
    var fetched_inbox = _this.get('fetched_inbox');
    if(updates.clears) {
      fetched_inbox.clears = (fetched_inbox.clears || []).concat(updates.clears);
    } 
    if(updates.reads) {
      fetched_inbox.reads = (fetched_inbox.reads || []).concat(updates.reads);
    }
    persistence.fetch_inbox(app_state.get('referenced_user'), {persist: fetched_inbox}).then(null, function(err) { debugger });
  },
  actions: {
    clear: function(which) {
      var alerts = [which];
      var _this = this;
      var clears = [];
      if(which == 'all') {
        alerts = _this.get('alerts') || [];
      }
      alerts.forEach(function(a) {
        stashes.log_event({
          alert: {
            alert_id: emberGet(a, 'id'),
            user_id: app_state.get('referenced_user.id'),
            cleared: true
          }
        }, app_state.get('referenced_user.id'));
        emberSet(a, 'cleared', true);
        clears.push(emberGet(a, 'id'));
      });
      _this.set('alerts', _this.get('alerts').filter(function(a) {
        return !emberGet(a, 'cleared');
      }))
      _this.update_inbox({clears: clears});
    },
    view: function(alert) {
      if(alert.note) {
        this.set('current', alert);
        var _this = this;
        emberSet(alert, 'unread', false);
        // persist the updated version of the inbox results
        stashes.log_event({
          alert: {
            alert_id: emberGet(alert, 'id'),
            user_id: app_state.get('referenced_user.id'),
            read: true
          }
        }, app_state.get('referenced_user.id'));
        _this.update_inbox({reads: [emberGet(alert, 'id')]});
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
