import app_state from '../utils/app_state';
import modal from '../utils/modal';
import persistence from '../utils/persistence';
import i18n from '../utils/i18n';

export default modal.ModalController.extend({
  opening: function() {
    if(app_state.get('sessionUser')) {
      this.set('cookies', !!app_state.get('sessionUser.preferences.cookies'));
    } else {
      this.set('cookies', localStorage['enable_cookies'] == 'true');
    }
  },
  ios: function() {
    return window.navigator.userAgent.match(/ipad|ipod|iphone/i);
  }.property(),
  actions: {
    toggle_cookies: function() {
      var _this = this;
      if(app_state.get('sessionUser')) {
        app_state.set('sessionUser.watch_cookies');
        app_state.set('sessionUser.preferences.cookies', !app_state.get('sessionUser.preferences.cookies'));
        app_state.get('sessionUser').save().then(function() {
          _this.set('cookies', !!app_state.get('sessionUser.preferences.cookies'));
        }, function() { });
      } else {
        app_state.toggle_cookies(localStorage['enable_cookies'] != 'true');
        this.set('cookies', localStorage['enable_cookies'] == 'true');
      }
    },
    submit_message: function() {
      if(!this.get('email') && !app_state.get('currentUser')) { return; }
      var message = {
        name: this.get('name'),
        email: this.get('email'),
        recipient: 'support',
        subject: this.get('subject'),
        message: this.get('message')
      };
      var _this = this;
      this.set('disabled', true);
      this.set('error', false);
      persistence.ajax('/api/v1/messages', {
        type: 'POST',
        data: {
          message: message
        }
      }).then(function(res) {
        _this.set('disabled', false);
        modal.success(i18n.t('message_delivered', "Message sent! Thank you for reaching out!"));
        modal.close();
      }, function() {
        _this.set('error', true);
        _this.set('disabled', false);
      });

    }
  }
});
