import Ember from 'ember';
import EmberObject from '@ember/object';
import { later as runLater, run } from '@ember/runloop';
import RSVP from 'rsvp';
import $ from 'jquery';
import stashes from './_stashes';
import CoughDrop from '../app';
import capabilities from './capabilities';
import persistence from './persistence';
import coughDropExtras from './extras';
import app_state from './app_state';
import i18n from './i18n';
import modal from './modal';

var session = EmberObject.extend({
  setup: function(application) {
    application.register('cough_drop:session', session, { instantiate: false, singleton: true });
    $.each(['model', 'controller', 'view', 'route'], function(i, component) {
      application.inject(component, 'session', 'cough_drop:session');
    });
    CoughDrop.session = session;
  },
  persist: function(data) {
    stashes.persist_object('auth_settings', data, true);
  },
  clear: function() {
    stashes.flush('auth_');
  },
  authenticate: function(credentials) {
    var _this = this;
    var res = new RSVP.Promise(function(resolve, reject) {
      var data = {
        grant_type: 'password',
        client_id: 'browser',
        client_secret: credentials.client_secret,
        username: credentials.identification,
        password: credentials.password,
        device_id: capabilities.device_id,
        long_token: credentials.long_token,
        mobile: (!!capabilities.mobile).toString()
      };

      persistence.ajax('/token', {method: 'POST', data: data}).then(function(response) {
        run(function() {
          session.persist({
            access_token: response.access_token,
            user_name: response.user_name,
            user_id: response.user_id
          });
          // update selfUserId, in the off chance that it has changed from our local copy
          // due to my user_name being renamed, and then me logging in to a new account
          // with the old user_name.
          if(response.user_id) {
            persistence.store('settings', {id: response.user_id}, 'selfUserId').then(null, function() {
              return RSVP.reject({error: "selfUserId not persisted from login"});
            });
          }
          stashes.persist_object('just_logged_in', true, false);
          resolve(response);
        });
      }, function(data) {
        var xhr = data.fakeXHR || {};
        run(function() {
          reject(xhr.responseJSON || xhr.responseText);
        });
      });
    });
    res.then(null, function() { });
    return res;
  },
  check_token: function(allow_invalidate) {
    var store_data = stashes.get_object('auth_settings', true) || {};
    var key = store_data.access_token || "none";
    persistence.tokens = persistence.tokens || {};
    persistence.tokens[key] = true;
    var url = '/api/v1/token_check?access_token=' + store_data.access_token;
    if(store_data.as_user_id) {
      url = url + "&as_user_id=" + store_data.as_user_id;
    }
    return persistence.ajax(url, {
      type: 'GET'
    }).then(function(data) {
      if(data.authenticated === false) {
        session.set('invalid_token', true);
        if(allow_invalidate) {
          session.force_logout(i18n.t('session_token_invalid', "This session is no longer valid, please log back in"));
        }
      } else {
        session.set('invalid_token', false);
      }
      if(data.user_name) {
        session.set('user_name', data.user_name);
        session.set('user_id', data.user_id);
        if(app_state.get('sessionUser.id') != data.user_id) {
          runLater(function() {
            app_state.refresh_session_user();
          });
        }
      }
      if(data.sale !== undefined) {
        CoughDrop.sale = parseInt(data.sale, 10) || false;
      }
      if(data.global_integrations) {
        stashes.persist('global_integrations', data.global_integrations);
        if(window.user_preferences) {
          window.user_preferences.global_integrations = data.global_integrations;
        }
      }
      if(data.meta && data.meta.fakeXHR && data.meta.fakeXHR.browserToken) {
        persistence.set('browserToken', data.meta.fakeXHR.browserToken);
      }
      return RSVP.resolve({browserToken: persistence.get('browserToken')});
    }, function(data) {
      if(!persistence.get('online')) {
        return;
      }
      if(data && data.fakeXHR && data.fakeXHR.browserToken) {
        persistence.set('browserToken', data.fakeXHR.browserToken);
      }
      if(data && data.result && data.result.error == "not online") {
        return;
      }
      persistence.tokens[key] = false;
      return RSVP.resolve({browserToken: persistence.get('browserToken')});
    });
  },
  restore: function(force_check_for_token) {
    if(!stashes.get('enabled')) { return {}; }
    console.debug('COUGHDROP: restoring session data');
    var store_data = stashes.get_object('auth_settings', true) || {};
    var key = store_data.access_token || "none";
    persistence.tokens = persistence.tokens || {};
    if(store_data.access_token && !session.get('isAuthenticated')) {
      session.set('isAuthenticated', true);
      session.set('access_token', store_data.access_token);
      session.set('user_name', store_data.user_name);
      session.set('user_id', store_data.user_id);
      session.set('as_user_id', store_data.as_user_id);
    } else if(!store_data.access_token) {
      // This should not run until stashes.db_connect has completed, to stashes has its
      // best chance to be populated.
      session.force_logout(i18n.t('session_lost', "Session data has been lost, please log back in"));
    }
    if(force_check_for_token || (persistence.tokens[key] == null && !Ember.testing && persistence.get('online'))) {
      if(store_data.access_token || force_check_for_token) { // || !persistence.get('browserToken')) {
        session.check_token(true);
      } else {
        session.set('tokenConfirmed', false);
      }
    }

    return store_data;
  },
  override: function(options) {
    var data = session.restore();
    data.access_token = options.access_token;
    data.user_name = options.user_name;
    data.user_id = options.user_id;
    stashes.flush();
    stashes.setup();
    session.persist(data);

    session.reload('/');
  },
  reload: function(path) {
    if(path) {
      if(Ember.testing) {
        console.error("would have redirected off the page");
      } else {
        if(capabilities.installed_app) {
          location.href = '#' + path;
          location.reload();
        } else {
          location.href = path;
        }
      }
    } else {
      location.reload();
    }
  },
  alert: function(message) {
    if(!Ember.testing) {
      alert(message);
    }
  },
  force_logout: function(message) {
    var full_invalidate = !!(app_state.get('currentUser') || stashes.get_object('auth_settings', true));
    if(full_invalidate) {
      if(!modal.route) {
        session.alert(message);
        session.invalidate(true);
      } else {
        modal.open('force-logout', {message: message});
      }
    } else {
      session.invalidate();
    }
  },
  invalidate: function(force) {
    var full_invalidate = force || !!(app_state.get('currentUser') || stashes.get_object('auth_settings', true));
    stashes.flush();
    stashes.setup();
    if(full_invalidate) {
      session.reload('/');
    }
    var _this = this;
    runLater(function() {
      session.set('isAuthenticated', false);
      session.set('access_token', null);
      session.set(' ', null);
      session.set('user_id', null);
      session.set('as_user_id', null);
    });
  }
}).create({
});
window.session = session;

export default session;
