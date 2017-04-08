import Ember from 'ember';
import persistence from '../../utils/persistence';
import modal from '../../utils/modal';
import i18n from '../../utils/i18n';

export default Ember.Controller.extend({
  refresh_lists: function() {
    this.load_blocked_emails();
    this.load_gifts();
  },
  load_gifts: function(more) {
    var _this = this;
    _this.set('gifts', {loading: true});
    _this.store.query('gift', {}).then(function(list) {
      _this.set('gifts', list);
    }, function(err) {
      _this.set('gifts', {error: true});
    });
  },
  load_blocked_emails: function() {
    var _this = this;
    _this.set('blocked_emails', {loading: true});
    persistence.ajax('/api/v1/organizations/' + this.get('model.id') + '/blocked_emails', {type: 'GET'}).then(function(res) {
      _this.set('blocked_emails', res.emails);
    }, function(err) {
      _this.set('blocked_emails', {error: true});
    });
  },
  actions: {
    block_email: function() {
      var email = this.get('blocked_email_address');
      var _this = this;
      if(email) {
        persistence.ajax('/api/v1/organizations/' + this.get('model.id') + '/extra_action', {
          type: 'POST',
          data: {
            extra_action: 'block_email',
            email: email
          }
        }).then(function(res) {
          if(res.success === false) {
            modal.error(i18n.t('blocking_email_failed', "Email address was not blocked"));
          } else {
            _this.set('blocked_email_address', null);
            _this.load_blocked_emails();
          }
        }, function(err) {
          modal.error(i18n.t('error_blocking_email', "There was an unexpected error while trying to add the blocked email address"));
        });
      }
    },
    add_gift: function(type) {
      var gift = this.store.createRecord('gift');
      if(type == 'purchase') {
        gift.set('amount', parseFloat(this.get('amount')));
        gift.set('licenses', parseInt(this.get('licenses'), 10));
        gift.set('organization', this.get('org'));
        gift.set('email', this.get('email'));
      } else {
        var years = parseFloat(this.get('duration')) || 3;
        gift.set('seconds', years * 365.25 * 24 * 60 * 60);
        gift.set('gift_name', this.get('gift_name'));
      }
      var _this = this;
      gift.save().then(function() {
        _this.load_gifts();
      }, function(err) {
        modal.error(i18n.t('error_creating_gift', "There was an error creating the custom purchase"));
      });
    }
  }
});
