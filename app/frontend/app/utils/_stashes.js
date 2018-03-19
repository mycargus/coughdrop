import Ember from 'ember';
import EmberObject from '@ember/object';
import { later as runLater, debounce as runDebounce } from '@ember/runloop';
import RSVP from 'rsvp';
import $ from 'jquery';
import CoughDrop from '../app';
// import i18n from './i18n';
// import modal from './modal';

// NOTE: there is an assumption that each stashed value is independent and
// non-critical, so for example if one attribute got renamed it would not
// break anything, or affect any other value.
var memory_stash = {};
var stash_capabilities = null;
var stashes = EmberObject.extend({
  connect: function(application) {
    application.register('cough_drop:stashes', stashes, { instantiate: false, singleton: true });
    $.each(['model', 'controller', 'view', 'route'], function(i, component) {
      application.inject(component, 'stashes', 'cough_drop:stashes');
    });
  },
  db_connect: function(cap) {
    stash_capabilities = cap;
    if(!cap.dbman) { return RSVP.resolve(); }
    return stash_capabilities.storage_find({store: 'settings', key: 'stash'}).then(function(stash) {
      var count = 0;
      for(var idx in stash) {
        if(idx != 'raw' && idx != 'storageId' && idx != 'changed' && stash[idx] !== undefined) {
          memory_stash[idx] = JSON.parse(stash[idx]);
          count++;
          stashes.set(idx, JSON.parse(stash[idx]));
        }
      }
      console.debug('COUGHDROP: restoring stashes from db, ' + count + ' values');
    }, function(err) {
      console.debug('COUGHDROP: db storage stashes not found');
      return RSVP.resolve();
    });
  },
  setup: function() {
    stashes.memory_stash = memory_stash;
    stashes.prefix = 'cdStash-';
    try {
      for(var idx = 0, l = localStorage.length; idx < l; idx++) {
        var key = localStorage.key(idx);
        if(key && key.indexOf(stashes.prefix) === 0) {
          var real_key = key.replace(stashes.prefix, '');
          try {
            memory_stash[real_key] = JSON.parse(localStorage[key]);
            stashes.set(real_key, JSON.parse(localStorage[key]));
          } catch(e) { }
        }
      }
      localStorage[stashes.prefix + 'test'] = Math.random();
      stashes.set('enabled', true);
    } catch(e) {
      stashes.set('enabled', false);
      if(console.debug) {
        console.debug('COUGHDROP: localStorage not working');
        console.debug(e);
      } else {
        console.log('COUGHDROP: localStorage not working');
        console.log(e);
      }
    }
    var defaults = {
      'working_vocalization': [],
      'current_mode': 'default',
      'usage_log': [],
      'daily_use': [],
      'boardHistory': [],
      'browse_history': [],
      'history_enabled': true,
      'root_board_state': null,
      'sidebar_enabled': false,
      'sticky_board': false,
      'remembered_vocalizations': [], // TODO: this should probably be remembered server-side, change when speaking as someone else
      'stashed_buttons': [],
      'ghost_utterance': false,
      'recent_boards': [],
      'logging_paused_at': null,
      'last_stream_id': null,
      'protected_user': false,
      'label_locale': null,
      'vocalization_locale': null,
      'global_integrations': null
    };
    // TODO: some of these will want to be retrieved from server stash, not just localstorage
    for(var idx in defaults) {
      var val = null;
      if(stashes.get('enabled')) {
        val = localStorage[stashes.prefix + idx] && JSON.parse(localStorage[stashes.prefix + idx]);
      }
      if(val === undefined || val === null) {
        val = defaults[idx];
      }
      stashes.set(idx, val);
      memory_stash[idx] = val;
    }
    if(stashes.get('global_integrations') && window.user_preferences) {
      window.user_preferences.global_integrations = stashes.get('global_integrations');
    } else if(!Ember.testing) {
      runLater(function() {
        if(CoughDrop && CoughDrop.session && CoughDrop.session.check_token) {
          CoughDrop.session.check_token();
        }
      }, 500);
    }
  },
  flush: function(prefix, ignore_prefix) {
    var full_prefix = stashes.prefix + (prefix || "");
    var full_ignore_prefix = ignore_prefix && (stashes.prefix + ignore_prefix);
    if((!prefix || prefix == 'auth_') && ignore_prefix != 'auth_') {
      stashes.flush_db_id();
    }
    if(stash_capabilities && stash_capabilities.dbman) {
      var stash = {};
      stash.storageId = 'stash';
      stash_capabilities.storage_store({store: 'settings', id: 'stash', record: stash});
    }
    for(var idx = 0, l = localStorage.length; idx < l; idx++) {
      var key = localStorage.key(idx);
      if(key && key.indexOf(full_prefix) === 0) {
        if(ignore_prefix && key.indexOf(full_ignore_prefix) === 0) {
        } else {
          try {
            stashes.set(key.replace(stashes.prefix, ''), undefined);
            delete memory_stash[key.replace(stashes.prefix, '')];
            localStorage.removeItem(key);
            idx--;
          } catch(e) { }
        }
      }
    }
  },
  db_persist: function() {
    if(stash_capabilities && stash_capabilities.dbman) {
      var stringed_stash = {};
      for(var idx in memory_stash) {
        stringed_stash[idx] = JSON.stringify(memory_stash[idx]);
      }
      stringed_stash.storageId = 'stash';
      // I intended for this to be a fallback in case localStorage data got lost
      // somehow, which is why the db id is also being stored in the cookie
      // as a fallback for the db id which is usually kept in localStorage.
      stash_capabilities.storage_store({store: 'settings', id: 'stash', record: stringed_stash});
    }
  },
  persist: function(key, obj) {
    if(!key) { return; }
    this.persist_object(key, obj, true);
    stashes.set(key, obj);

    if(memory_stash[key] != obj) {
      memory_stash[key] = obj;
      runDebounce(this, this.db_persist, 500);
    }
  },
  persist_object: function(key, obj, include_prefix) {
    var _this = this;
    // Why aren't we using client-side encryption, you ask?
    // http://matasano.com/articles/javascript-cryptography/
    // Since the encryption key would have to be stored in either localStorage
    // or IndexedDB, anyone who has access to the datastores also has
    // access to the unprotected encryption key.
    stashes.persist_raw(key, JSON.stringify(obj), include_prefix);

    if(key == 'auth_settings' && obj.user_name) {
      document.cookie = "authDBID=" + obj.user_name;
      if(window.kvstash && window.kvstash.store) {
        window.kvstash.store('user_name', obj.user_name);
      }
    }
  },
  flush_db_id: function() {
    document.cookie = 'authDBID=';
    if(window.kvstash && window.kvstash.remove) {
      window.kvstash.remove('user_name');
    }
  },
  persist_raw: function(key, obj, include_prefix) {
    if(include_prefix) { key = stashes.prefix + key; }
    try {
      localStorage[key] = obj.toString();
    } catch(e) { }
  },
  get_object: function(key, include_prefix) {
    var res = null;
    try {
      res = JSON.parse(stashes.get_raw(key, include_prefix)) || this.get(key);
    } catch(e) { }
    return res;
  },
  get_db_id: function(cap) {
    var auth_settings = stashes.get_object('auth_settings', true);
    if(auth_settings) {
      return auth_settings.user_name;
    } else {
      var keys = (document.cookie || "").split(/\s*;\s*/);
      var key = keys.find(function(k) { return k.match(/^authDBID=/); });
      var user_name = key && key.replace(/^authDBID=/, '');
      if(user_name) {
        return user_name;
      } else if(cap && window.kvstash && window.kvstash.values) {
        return window.kvstash.values.user_name || null;
      } else {
        return null;
      }
    }
  },
  get_db_key: function(persist) {
    var key = stashes.get_raw('cd_db_key');
    if(persist) {
      key = key || ("db2_" + Math.random().toString() + "_" + (new Date()).getTime().toString());
      stashes.persist_raw('cd_db_key', key);
    }
    return key
  },
  get_raw: function(key, include_prefix) {
    if(include_prefix) { key = stashes.prefix + key; }
    var res = null;
    try {
      res = localStorage[key];
    } catch(e) { }
    return res;
  },
  geo: {
    poll: function() {
      if(stashes.geolocation && !CoughDrop.embedded) {
        if(stashes.geo.watching) {
          stashes.geolocation.clearWatch(stashes.geo.watching);
        }
        stashes.geolocation.getCurrentPosition(function(position) {
          stashes.set('geo.latest', position);
        });
        stashes.geo.watching = stashes.geolocation.watchPosition(function(position) {
          stashes.set('geo.latest', position);
        }, function(error) {
          stashes.set('geo.latest', null);
        });
      }
    }
  },
  remember: function() {
    if(!stashes.get('history_enabled')) { return; }
    // TODO: this should be persisted server-side
    var list = stashes.get('remembered_vocalizations');
    if(stashes.get('working_vocalization').length === 0) { return; }
    var obj = {
      vocalizations: stashes.get('working_vocalization')
    };
    obj.sentence = obj.vocalizations.map(function(v) { return v.label; }).join(" ");
    if(!list.find(function(v) { return v.sentence == obj.sentence; })) {
      list.pushObject(obj);
    }
    stashes.persist('remembered_vocalizations', list);
  },
  current_timestamp: function() {
    return Date.now() / 1000;
  },
  notify_observers(button) {
    if(window.parent && window.parent != window && CoughDrop.embedded) {
      window.parent.postMessage({
        type: 'aac_event',
        aac_type: 'button',
        text: button.vocalization || button.label,
        sentence: stashes.get('working_vocalization').map(function(b) { return b.vocalization || b.label; }).join(" ")
      }, '*');
    }
  },
  log_event: function(obj, user_id) {
    var timestamp = stashes.current_timestamp();
    var geo = null;
    if(stashes.geo && stashes.get('geo.latest') && stashes.get('geo_logging_enabled')) { // TODO: timeout if it's been too long?
      geo = [stashes.get('geo.latest').coords.latitude, stashes.get('geo.latest').coords.longitude, stashes.get('geo.latest').coords.altitude];
    }
    var log_event = null;
    var usage_log = stashes.get('usage_log');
    if(obj && user_id) {
      if(obj.buttons) {
        log_event = {
          type: 'utterance',
          timestamp: timestamp,
          user_id: user_id,
          geo: geo,
          utterance: obj
        };
      } else if(obj.button_id) {
        log_event = {
          type: 'button',
          timestamp: timestamp,
          user_id: user_id,
          geo: geo,
          button: obj
        };
        stashes.notify_observers(obj);
      } else if(obj.tallies) {
        log_event = {
          type: 'assessment',
          timestamp: timestamp,
          user_id: user_id,
          geo: geo,
          assessment: obj
        };
      } else if(obj.note) {
        log_event = {
          type: 'note',
          timestamp: timestamp,
          user_id: user_id,
          geo: geo,
          note: obj
        };
      } else {
        log_event = {
          type: 'action',
          timestamp: timestamp,
          user_id: user_id,
          geo: geo,
          action: obj
        };
      }
      if(stash_capabilities) {
        log_event.system = stash_capabilities.system;
        log_event.browser = stash_capabilities.browser;
      }
      if(stashes.orientation) {
        log_event.orientation = stashes.orientation;
      }
      if(stashes.volume !== null && stashes.volume !== undefined) {
        log_event.volume = stashes.volume;
      }
      if(stashes.ambient_light !== null && stashes.ambient_light !== undefined) {
        log_event.ambient_light = stashes.ambient_light;
      }
      if(stashes.screen_brightness) {
        log_event.screen_brightness = stashes.screen_brightness;
      }
      if(stashes.get('referenced_user_id')) {
        log_event.referenced_user_id = stashes.get('referenced_user_id');
      }
      if(stashes.get('modeling') || (log_event.button && log_event.button.modeling)) {
        log_event.modeling = true;
      } else if(stashes.last_selection && stashes.last_selection.modeling && stashes.last_selection.ts > ((new Date()).getTime() - 500)) {
        log_event.modeling = true;
      }
      log_event.window_width = window.outerWidth;
      log_event.window_height= window.outerHeight;

      if(log_event) {
        stashes.persist('last_event', log_event);
        usage_log.push(log_event);
      }
    }
    stashes.persist('usage_log', usage_log);
    stashes.push_log(true);
    return log_event;
  },
  track_daily_use: function() {
    var now = (new Date()).getTime();
    var today = window.moment().toISOString().substring(0, 10);
    var daily_use = stashes.get('daily_use') || [];
    var found = false;
    daily_use.forEach(function(d) {
      if(d.date == today) {
        found = d;
        // if it's been less than 5 minutes since the last event, add the difference
        // to the total minutes for the day, otherwise just say we've had a teeny
        // bit of activity.
        if(now - d.last_timestamp < (5 * 60 * 1000)) {
          d.total_minutes = (d.total_minutes || 0) + ((now - d.last_timestamp) / (60 * 1000));
        } else {
          d.total_minutes = (d.total_minutes || 0) + 0.25;
        }
        d.last_timestamp = now;
      }
    });
    if(!found) {
      daily_use.push({
        date: today,
        last_timestamp: now,
        total_minutes: 0.25,
        recorded_minutes: 0
      });
    }
    stashes.persist('daily_use', daily_use);
    // once we have data for more than one day, or at least 10 new minutes of usage, push it and then clear the history
    var do_push = daily_use.length > 1 || (found && (found.total_minutes - found.recorded_minutes) > 10);
    if(daily_use.length > 1 && stashes.get('online')) {
      if(found) {
        found.recorded_minutes = found.total_minutes;
      }
      var days = [];
      daily_use.forEach(function(d) {
        var level = 0;
        if(d.total_minutes >= 60) { level = 5; }
        else if(d.total_minutes >= 30) { level = 4; }
        else if(d.total_minutes >= 15) { level = 3; }
        else if(d.total_minutes >= 5) { level = 2; }
        else if(d.total_minutes > 0) { level = 1; }
        days.push({
          date: d.date,
          activity_level: level,
          active: d.total_minutes >= 30
        });
      });
      // ajax call to push daily_use data
      var log = CoughDrop.store.createRecord('log', {
        type: 'daily_use',
        events: days
      });
      log.save().then(function() {
        // clear the old days that have been persisted
        var dailies = stashes.get('daily_use') || [];
        dailies = dailies.filter(function(d) { return d == today; });
        stashes.persist('daily_use', dailies);
      }, function() { });
    }
  },
  log: function(obj) {
    stashes.track_daily_use();
    if(!stashes.get('history_enabled')) { return null; }
    if(!stashes.get('logging_enabled')) { return null; }
    if(stashes.get('logging_paused_at')) {
      var last_event = stashes.get('last_event');
      var pause = stashes.get('logging_paused_at');
      var sixty_minutes_ago = (new Date()).getTime() - (60 * 60 * 1000);
      var six_hours_ago = (new Date()).getTime() - (6 * 60 * 60 * 1000);
      if(last_event && last_event.timestamp > pause && last_event < sixty_minutes_ago) {
//         modal.warning(i18n.t('logging_resumed', "Logging has resumed automatically after at least an hour of inactivity"));
        if(stashes.controller) {
          stashes.controller.set('logging_paused_at', null);
        }
        stashes.persist('logging_paused_at', null);
      } else if(last_event && last_event.timestamp > pause && last_event < six_hours_ago) {
//         modal.warning(i18n.t('logging_resumed', "Logging has resumed automatically after being paused for over six hours"));
        if(stashes.controller) {
          stashes.controller.set('logging_paused_at', null);
        }
        stashes.persist('logging_paused_at', null);
      } else {
        return null;
      }
    }
    var user_id = stashes.get('speaking_user_id');
    if(stashes.get('referenced_speak_mode_user_id')) {
      user_id = stashes.get('referenced_speak_mode_user_id');
    }
    return stashes.log_event(obj, user_id);
  },
  push_log: function(only_if_convenient) {
    var usage_log = stashes.get('usage_log');
    var timestamp = stashes.current_timestamp();
    // Remove from local store and persist occasionally
    var diff = (usage_log && usage_log[0] && usage_log[0].timestamp) ? (timestamp - usage_log[0].timestamp) : -1;
    // If log pushes have been failing, don't keep trying on every button press
    var wait_on_error = stashes.errored_at && stashes.errored_at > 10 && ((timestamp - stashes.errored_at) < (2 * 60));
    // TODO: add listener on persistence.online and trigger this log save stuff when reconnected
    if(CoughDrop.session && CoughDrop.session.get('isAuthenticated') && stashes.get('online') && usage_log.length > 0 && !wait_on_error) {
      // If there's more than 10 events, or it's been more than 1 hour
      // since the last recorded event.
      if(usage_log.length > 10 || diff == -1 || diff > (60 * 60 * 1000) || !only_if_convenient) {
        var history = [].concat(usage_log);
        // If there are tons of events, break them up into smaller chunks, this may
        // be why user logs stopped getting persisted for one user's device.
        var to_persist = history.slice(0, 250);
        var for_later = history.slice(250, history.length);
        stashes.persist('usage_log', for_later);
        var log = CoughDrop.store.createRecord('log', {
          events: to_persist
        });
        log.cleanup();
        log.save().then(function() {
          stashes.errored_at = null;
          if(for_later.length > 0) {
            runLater(function() {
              stashes.push_log();
            });
          }
          // success!
        }, function(err) {
          // error, try again later
          if(!stashes.errored_at || stashes.errored_at <= 2) {
//             stashes.persist('usage_log', to_persist.concat(stashes.get('usage_log')));
            stashes.errored_at = (stashes.errored_at || 0) + 1;
          } else {
//             stashes.set('big_logs', (stashes.get('big_logs') || []).concat([to_persist]));
            stashes.errored_at = stashes.current_timestamp();
          }
          console.log(err);
          console.error("log push failed");
          stashes.persist('usage_log', to_persist.concat(stashes.get('usage_log')));
        });
      }
    }
    if(!stashes.timer) {
      stashes.timer = runLater(function() {
        stashes.timer = null;
        stashes.push_log(only_if_convenient);
      }, 30 * 60 * 1000);
    }
  }
}).create({logging_enabled: false});
stashes.setup();
stashes.geolocation = navigator.geolocation;

window.stashes = stashes;

export default stashes;
