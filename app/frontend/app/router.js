import Ember from 'ember';
import config from './config/environment';
import capabilities from './utils/capabilities';

var use_push_state = !!(window.history && window.history.pushState);
if(location.pathname.match(/^\/jasmine/)) {
  use_push_state = false;
} else if(capabilities.browserless) {
  use_push_state = false;
} else if(window.navigator.standalone) {
  use_push_state = false;
} else if(false) { // TODO: check if full screen launch on android
  use_push_state = false;
}
if(Ember.testing) {
  config.locationType = 'none';
} else if(capabilities.installed_app) {
  config.locationType = 'hash';
} else if(use_push_state) {
  config.locationType = 'history';
}
var Router = Ember.Router.extend({
  location: config.locationType,
  rootURL: config.rootURL
});

Router.reopen({
  notifyGoogleAnalytics: function() {
    if(window.ga) {
      return window.ga('send', 'pageview', {
        'page': this.get('url'),
        'title': this.get('url')
      });
    }
  }.on('didTransition')
});

Router.map(function() {
  this.route('jasmine');
  this.route('index', { path: '/' });
  this.route('about', { path: '/about' });
  this.route('download', { path: '/download' });
  this.route('terms', { path: '/terms' });
  this.route('privacy', { path: '/privacy' });
  this.route('jobs', { path: '/jobs' });
  this.route('pricing', { path: '/pricing' });
  this.route('contact', { path: '/contact' });
  this.route('home-boards', { path: '/search/home' });
  this.route('search', { path: '/search/:q' });
  this.route('login');
  this.route('register');
  this.route('intro');
  this.route('forgot_password');
  this.route('forgot_login');
  this.route('partners');
  this.route('compare');
  this.route('ambassadors');
  this.route('utterance', { path: '/utterances/:id' });
  this.route('admin', { path: '/admin' });
  this.route('organization', { path: '/organizations/:id' }, function() {
    this.route('reports');
    this.route('subscription');
    this.route('extras');
    this.route('rooms');
    this.route('room', { path: '/rooms/:room_id' });
  });
  this.route('goals', { path: '/goals' }, function() {
      this.route('goal', { path: '/:goal_id' });
  });
  this.route('redeem', { path: '/redeem' });
  this.route('redeem_with_code', { path: '/redeem/:code' });
  this.route('gift_purchase', { path: '/gift' });
  this.route('bulk_purchase', { path: '/purchase/:id'});
  this.route('troubleshooting', { path: '/troubleshooting' });
  this.route('user', { resetNamespalce: true, path: '/:user_id' }, function() {
    this.route('edit');
    this.route('preferences');
    this.route('subscription');
    this.route('stats');
    this.route('goals');
    this.route('goal', { path: '/goals/:goal_id' });
    this.route('recordings');
    this.route('logs');
    this.route('log', { path: '/logs/:log_id' });
    this.route('badges');
    this.route('device');
    this.route('history');
    this.route('confirm_registration', { path: '/confirm_registration/:code' });
    this.route('password_reset', { path: '/password_reset/:code' });
  });
  this.route('board', { resetNamespace: true, path: '/*key'}, function() {
//    this.route('error');
    this.route('stats');
    this.route('history');
  });
//  this.route('board_error');
});

export default Router;
