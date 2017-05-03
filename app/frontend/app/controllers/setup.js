import Ember from 'ember';
import i18n from '../utils/i18n';
import persistence from '../utils/persistence';
import CoughDrop from '../app';
import app_state from '../utils/app_state';
import modal from '../utils/modal';
import speecher from '../utils/speecher';
import utterance from '../utils/utterance';
import Utils from '../utils/misc';
import Stats from '../utils/stats';

var order = ['intro', 'usage', 'home_boards', 'core', 'symbols', 'access', 'board_category', 'voice', 'logging', 'supervisors', 'notifications', 'done'];
var extra_order = ['extra-dashboard', 'extra-home-boards', 'extra-speak-mode', 'extra-folders', 'extra-exit-speak-mode', 'extra-modeling', 'extra-supervisors', 'extra-reports', 'extra-logs', 'extra-done'];
export default Ember.Controller.extend({
  speecher: speecher,
  title: function() {
    return i18n.t('account_setup', "Account Setup");
  }.property(),
  queryParams: ['page', 'finish'],
  order: order,
  extra_order: extra_order,
  partial: function() {
    var page = this.get('page');
    var pages = order.concat(extra_order);
    if(page && page.match(/^extra/)) {
      app_state.controller.set('setup_order', order.concat(extra_order));
    }
    if(pages.indexOf(page) != -1) {
      return "setup/" + page;
    } else {
      return "setup/intro";
    }
  }.property('page'),
  text_position: function() {
    var res = {};
    if(this.get('app_state.currentUser.preferences.device.button_text_position') == 'top') {
      res.text_on_top = true;
    } else if(this.get('app_state.currentUser.preferences.device.button_text_position') == 'bottom') {
      res.text_on_bottom = true;
    } else if(this.get('app_state.currentUser.preferences.device.button_text_position') == 'text_only') {
      res.text_only = true;
    }
    return res;
  }.property('app_state.currentUser.preferences.device.button_text_position'),
  access: function() {
    var res = {};
    if(this.get('app_state.currentUser.preferences.device.dwell')) {
      res.dwell = true;
    } else if(this.get('app_state.currentUser.preferences.device.scanning')) {
      res.scanning = true;
    } else {
      res.touch = true;
    }
    return res;
  }.property('app_state.currentUser.preferences.device.dwell', 'app_state.currentUser.preferences.device.scanning'),
  notification: function() {
    var res = {};
    if(app_state.get('currentUser.preferences.notification_frequency') == '1_week') {
      res['1_week'] = true;
    } else if(app_state.get('currentUser.preferences.notification_frequency') == '2_weeks') {
      res['2_weeks'] = true;
    } else if(app_state.get('currentUser.preferences.notification_frequency') == '1_month') {
      res['1_month'] = true;
    } else {
      res['none'] = true;
    }
    if(app_state.get('currentUser.preferences.share_notifications') == 'email') {
      res.email = true;
    } else if(app_state.get('currentUser.preferences.share_notifications') == 'text') {
      res.text = true;
    } else if(app_state.get('currentUser.preferences.share_notifications') == 'app') {
      res.app = true;
    } else {
      res.email = true;
    }
    return res;
  }.property('app_state.currentUser.preferences.notification_frequency', 'app_state.currentUser.preferences.share_notifications'),
  update_cell: function() {
    if(!this.get('cell') && app_state.get('currentUser.cell_phone')) {
      this.set('cell', app_state.get('currentUser.cell_phone'));
    } else {
      app_state.currentUser.set('cell_phone', this.get('cell'));
      this.send('set_preference', 'cell_phone', this.get('cell'));
    }
  }.observes('cell', 'app_state.currentUser.cell_phone'),
  update_pin: function() {
    if(!this.get('pin') && app_state.get('currentUser.preferences.speak_mode_pin') && app_state.get('currentUser.preferences.require_speak_mode_pin')) {
      this.set('pin', app_state.get('currentUser.preferences.speak_mode_pin') || "");
    } else {
      var pin = (parseInt(this.get('pin'), 10) || "").toString().substring(0, 4);
      var _this = this;
      Ember.run.later(function() {
        if(pin != _this.get('pin')) {
          _this.set('pin', pin);
        }
      }, 10);
      if(pin.length == 4 && (!app_state.get('currentUser.preferences.require_speak_mode_pin') || pin != app_state.get('currentUser.preferences.speak_mode_pin'))) {
        app_state.set('currentUser.preferences.require_speak_mode_pin', true);
        this.send('set_preference', 'speak_mode_pin', this.get('pin'));
      } else if(pin.length != 4 && app_state.get('currentUser.preferences.require_speak_mode_pin')) {
        this.send('set_preference', 'require_speak_mode_pin', false);
      }
    }
  }.observes('pin', 'app_state.currentUser.preferences.require_speak_mode_pin', 'app_state.currentUser.preferences.speak_mode_pin'),
  update_checkbox_preferences: function() {
    var do_update = false;
    var _this = this;
    ['vocalize_buttons', 'vocalize_linked_buttons', 'auto_home_return'].forEach(function(pref) {
      if(_this.get(pref) == null && app_state.get('currentUser.preferences.' + pref)) {
        _this.set(pref, app_state.get('currentUser.preferences.' + pref));
      } else if(_this.get(pref) != null && _this.get(pref) != app_state.currentUser.get('preferences.' + pref)) {
        console.log(pref, 'changed!', _this.get(pref));
        app_state.set('currentUser.preferences.' + pref, _this.get(pref));
        do_update = true;
      }
    });
    if(do_update) {
      this.send('set_preference', 'extra', true);
    }
  }.observes('app_state.currentUser.preferences.vocalize_buttons', 'vocalize_buttons', 'app_state.currentUser.preferences.vocalize_linked_buttons', 'vocalize_linked_buttons', 'app_state.currentUser.preferences.auto_home_return', 'auto_home_return'),
  user_voice_list: function() {
    var list = speecher.get('voiceList');
    var result = [];
    var premium_voice_ids = (this.get('app_state.currentUser.premium_voices.claimed') || []).map(function(id) { return "extra:" + id; });
    var voice_uri = this.get('app_state.currentUser.preferences.device.voice.voice_uri');
    var found = false;
    list.forEach(function(voice) {
      voice = Ember.$.extend({}, voice);
      voice.selected = voice.id == voice_uri;
      if(voice.selected) { found = true; }
      if(voice.voiceURI && voice.voiceURI.match(/^extra/)) {
        if(premium_voice_ids.indexOf(voice.voiceURI) >= 0) {
          result.push(voice);
        }
      } else {
        result.push(voice);
      }
    });
    if(result.length > 1) {
      result.push({
        id: 'force_default',
        name: i18n.t('system_default_voice', 'System Default Voice'),
        selected: !found
      });
    }
    return result;
  }.property('speecher.voiceList', 'app_state.currentUser.premium_voices.claimed', 'app_state.currentUser.preferences.device.voice.voice_uris'),
  update_on_page_change: function() {
    this.send('set_category', 'robust');
    this.set('show_category_explainer', false);
    this.set('cell', app_state.get('currentUser.cell_phone'));
    var _this = this;
    ['vocalize_buttons', 'vocalize_linked_buttons', 'auto_home_return'].forEach(function(pref) {
      _this.set(pref, app_state.get('currentUser.preferences.' + pref));
    });
    app_state.controller.set('setup_page', this.get('page'));
    Ember.$('html,body').scrollTop(0);
  }.observes('page'),
  actions: {
    set_preference: function(preference, value) {
      var user = app_state.get('currentUser');
      if(preference == 'access') {
        if(value == 'touch') {
          user.set('preferences.device.dwell', false);
          user.set('preferences.device.scanning', false);
        } else if(value == 'dwell') {
          user.set('preferences.device.dwell', true);
          user.set('preferences.device.scanning', false);
        } else if(value == 'scanning') {
          user.set('preferences.device.dwell', false);
          user.set('preferences.device.scanning', true);
        }
      } else {
        user.set('preferences.' + preference, value);
      }
      var _this = this;
      if(preference == 'logging' && value === true) {
        modal.open('enable-logging', {save: true, user: app_state.get('currentUser')});
      }
      app_state.controller.set('footer_status', {message: i18n.t('updating_user', "Updating User...")});
      user.save().then(function() {
        app_state.controller.set('footer_status', null);
      }, function(err) {
        app_state.controller.set('footer_status', {error: i18n.t('error_updating_user', "Error Updating User")});
      });
    },
    home: function(plus_video) {
      this.transitionToRoute('index');
      if(plus_video) {
        modal.open('inline-video', {video: {url: "https://www.youtube.com/embed/gsxfLVhUbus?rel=0"}, hide_overlay: true});
      }
    },
    test_voice: function() {
      utterance.test_voice(app_state.get('currentUser.preferences.device.voice.voice_uri'), app_state.get('currentUser.preferences.device.voice.rate'), app_state.get('currentUser.preferences.device.voice.pitch'), app_state.get('currentUser.preferences.device.voice.volume'));
    },
    premium_voices: function() {
      var _this = this;
      modal.open('premium-voices', {user: app_state.get('currentUser')});
    },
    set_category: function(str) {
      var res = {};
      res[str] = true;
      this.set('current_category', str);
      this.set('category', res);
      this.set('show_category_explainer', false);
      this.set('category_boards', {loading: true});
      var _this = this;
      _this.store.query('board', {public: true, starred: true, user_id: 'example', sort: 'custom_order', per_page: 6, category: str}).then(function(data) {
        _this.set('category_boards', data);
      }, function(err) {
        _this.set('category_boards', {error: true});
      });
    },
    more_for_category: function() {
      var _this = this;
      _this.set('more_category_boards', {loading: true});
      _this.store.query('board', {public: true, sort: 'home_popularity', per_page: 9, category: this.get('current_category')}).then(function(data) {
        _this.set('more_category_boards', data);
      }, function(err) {
        _this.set('more_category_boards', {error: true});
      });
    },
    show_explainer: function() {
      this.set('show_category_explainer', true);
    },
    extra: function() {
      app_state.controller.set('setup_order', order.concat(extra_order));
      Ember.run.later(function() {
        app_state.controller.send('setup_go', 'forward');
      });
    }
  }
});
