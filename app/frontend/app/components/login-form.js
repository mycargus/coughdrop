import Ember from 'ember';
import capabilities from '../utils/capabilities';
import stashes from '../utils/_stashes';
import persistence from '../utils/persistence';
import i18n from '../utils/i18n';
import app_state from '../utils/app_state';
import session from '../utils/session';

export default Ember.Component.extend({
  willInsertElement: function() {
    var _this = this;
    this.set('stashes', stashes);
    this.set('checking_for_secret', false);
    this.browserTokenChange = function() {
      _this.set('client_id', 'browser');
      _this.set('client_secret', persistence.get('browserToken'));
      _this.set('checking_for_secret', false);
    };
    persistence.addObserver('browserToken', this.browserTokenChange);
    this.set('long_token', false);
    var token = persistence.get('browserToken');
    if(token) {
      this.set('client_id', 'browser');
      this.set('client_secret', token);
    } else {
      this.set('checking_for_secret', true);
      var timeout = this.get('restore') === false ? 100 : 2000;
      Ember.run.later(function() {
        _this.check_for_missing_token();
      }, timeout);
      if(this.get('restore') !== false) {
        session.restore(true);
      }
    }
    if(this.get('set_overflow')) {
      Ember.$("html,body").css('overflow', 'hidden');
    }
  },
  check_for_missing_token: function() {
    var _this = this;
    _this.set('checking_for_secret', false);
    if(!_this.get('client_secret')) {
      session.check_token().then(function() {
        Ember.run.later(function() {
          _this.check_for_missing_token();
        }, 2000);
      }, function() {
        Ember.run.later(function() {
          _this.check_for_missing_token();
        }, 2000);
      });
    }
  },
  app_state: function() {
    return app_state;
  }.property(),
  persistence: function() {
    return persistence;
  }.property(),
  willDestroyElement: function() {
    persistence.removeObserver('browserToken', this.browserTokenChange);
  },
  browserless: function() {
    return capabilities.browserless;
  }.property(),
  noSubmit: function() {
    return this.get('noSecret') || this.get('logging_in') || this.get('logged_in');
  }.property('logging_in', 'logged_in', 'noSecret'),
  noSecret: function() {
    return !this.get('client_secret');
  }.property('client_secret'),
  actions: {
    authenticate: function() {
      this.set('logging_in', true);
      this.set('login_error', null);
      var data = this.getProperties('identification', 'password', 'client_secret', 'long_token', 'browserless');
      if(capabilities.browserless || capabilities.installed_app) {
        data.long_token = true;
        data.browserless = true;
      }
      if (!Ember.isEmpty(data.identification) && !Ember.isEmpty(data.password)) {
        this.set('password', null);
        var _this = this;
        session.authenticate(data).then(function(data) {
          stashes.flush(null, 'auth_');
          stashes.setup();
          _this.set('logging_in', false);
          _this.set('logged_in', true);
          if(Ember.testing) {
            console.error("would have redirected to home");
          } else {
            if(_this.get('return')) {
              location.reload();
              session.set('return', true);
            } else if(capabilities.installed_app) {
              location.href = '#/';
              location.reload();
            } else {
              location.href = '/';
            }
          }
        }, function(err) {
          err = err || {};
          _this.set('logging_in', false);
          if(err.error == "Invalid authentication attempt") {
            _this.set('login_error', i18n.t('invalid_login', "Invalid user name or password"));
          } else if(err.error == "Invalid client secret") {
            _this.set('login_error', i18n.t('invalid_login', "Your login token is expired, please try again"));
          } else {
            _this.set('login_error', i18n.t('login_error', "There was an unexpected problem logging in"));
          }
        });
      } else {
        this.set('login_error', i18n.t('login_required', "Username and password are both required"));
        this.set('logging_in', false);
      }
    }
  }
});
