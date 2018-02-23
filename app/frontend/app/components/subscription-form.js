import Ember from 'ember';
import Component from '@ember/component';
import Subscription from '../utils/subscription';
import modal from '../utils/modal';
import persistence from '../utils/persistence';
import progress_tracker from '../utils/progress_tracker';
import app_state from '../utils/app_state';
import session from '../utils/session';
import capabilities from '../utils/capabilities';
import i18n from '../utils/i18n';

export default Component.extend({
  update_classes: Subscription.obs_func.observes.apply(Subscription.obs_func, Subscription.obs_properties),
  didInsertElement: function() {
    if(this.$().width() < 850) {
      this.$().addClass('skinny_subscription');
    }
    this.set('session', session);
    this.set('see_pricing', false);
    session.check_token();

    if((this.get('session.invalid_token') || !capabilities.access_token) && !this.get('pricing_only')) {
      console.error('subscription_missing_access_token');
      this.set('not_authenticated', true);
    }
    this.update_classes();
  },
  trial_choice: function() {
    return this.get('trial_option') && !this.get('see_pricing') && !this.get('subscription.user.really_expired');
  }.property('trial_option', 'see_pricing', 'subscription.user.really_expired'),
  update_not_authenticated: function() {
    if(!this.get('pricing_only') && this.get('session.invalid_token')) {
      this.set('not_authenticated', true);
    }
  }.observes('session.invalid_token', 'pricing_only'),
  actions: {
    toggle_explanation: function(type) {
      this.set('explanation_' + type, !this.get('explanation_' + type));
    },
    show_expiration_notes: function() {
      this.set('show_expiration_notes', true);
    },
    show_alternative_pricing: function() {
      this.set('show_alternative_pricing', !this.get('show_alternative_pricing'));
    },
    skip_subscription: function() {
      var role = this.get('subscription.user_type');
      var user = this.get('user');
      user.set('preferences.role', role);
      var progress = user.get('preferences.progress') || {};
      progress.skipped_subscribe_modal = true;
      user.set('preferences.progress', progress);
      user.save().then(null, function() { });
      // TODO: this really belongs in the modal controller
      this.sendAction('subscription_skip');
    },
    reload: function() {
      location.reload();
    },
    logout: function() {
      session.invalidate(true);
    },
    reset: function() {
      this.get('subscription').reset();
    },
    set_user_type: function(type) {
      this.set('subscription.user_type', type);
    },
    set_subscription_type: function(type) {
      if(type && (type.match(/communicator/) || type.match(/gift_code/))) {
        this.set('subscription.user_type', 'communicator');
        type = type.replace(/_communicator/, '');
      }
      this.set('subscription.subscription_type', type);
    },
    set_special_subscription: function() {
      this.set('subscription.special_type', !this.get('subscription.special_type'));
    },
    set_subscription: function(amount) {
      if(amount && amount.match(/slp/)) {
        this.set('subscription.user_type', 'supporter');
      }
      this.set('subscription.subscription_amount', amount);
    },
    bulk_purchase: function() {
      this.set('show_bulk_purchase', !this.get('show_bulk_purchase'));
    },
    show_options: function() {
      this.set('subscription.show_options', true);
      this.set('subscription.show_cancel', false);
    },
    check_pricing: function() {
      this.set('see_pricing', true);
    },
    purchase: function() {
      var subscription = this.get('subscription');
      var user = this.get('user');
      if(!Subscription.ready || !subscription || !user) {
        modal.error(i18n.t('purchasing_not_read', "There was a problem initializing the purchasing system. Please contact support."));
        return;
      } else if(!subscription.get('valid')) {
        return;
      }
      var _this = this;
      var subscribe = function(token, type) {
        subscription.set('finalizing_purchase', true);
        persistence.ajax('/api/v1/users/' + user.get('user_name') + '/subscription', {
          type: 'POST',
          data: {
            token: token,
            type: type,
            confirmation: subscription.get('confirmation')
          }
        }).then(function(data) {
          progress_tracker.track(data.progress, function(event) {
            if(event.status == 'errored') {
              _this.sendAction('subscription_error', i18n.t('user_subscription_update_failed', "Purchase failed. Please try again or contact support for help."));
              _this.send('reset');
              console.log(event);
              if(event.sub_status == 'server_unresponsive') {
                console.error('purchase_server_timeout');
              } else {
                console.error('purchase_progress_failed');
              }
            } else if(event.status == 'finished' && event.result && event.result.success === false && event.result.error == 'card_declined') {
              var str = i18n.t('card_declined', "Purchase failed, your card was declined. Please try a different card or contact support for help.");
              if(event.result.decline_code && event.result.decline_code == 'fraudulent') {
                str = i18n.t('card_declined_by_billing', "Purchase failed, our billing system has flagged your card as high-risk. Please try a different card or contact support for help.");
              }
              _this.sendAction('subscription_error', str);
              _this.send('reset');
              console.log(event);
            } else if(event.status == 'finished') {
              if(user.get('preferences')) {
                user.reload().then(function() {
                  user.set('preferences.progress.subscription_set', true);
                  user.save();
                  _this.send('reset');
                  _this.sendAction('subscription_success', i18n.t('user_subscribed', "Your purchase succeeded! Thank you for supporting CoughDrop!"));
                }, function() {
                  _this.sendAction('subscription_error', i18n.t('user_subscription_reload_failed', "Purchase succeeded, but there was a problem reloading your user account. Please try loading this page again."));
                });
              } else {
                location.reload();
              }
            }
          });
        }, function(err) {
          console.log(err);
          console.error('purchase_subscription_start_failed');
          _this.send('reset');
          var message = (err.result && err.result.error) || err.error || err;
          if(message && message.match(/Access token required/)) {
            console.error('purchase_subscription_missing_token');
            _this.sendAction('subscription_authentication_error', i18n.t('user_subscription_unauthenticated', "Purchase failed, it looks like your login may have timed out. Please try logging out and back in. If that doesn't help, please contact support and we'll help figure things out."));
          } else {
            _this.sendAction('subscription_error', i18n.t('user_subscription_update_failed', "Purchase failed unexpectedly. Please try logging out and back in. If that doesn't work, please contact support for help."));
          }
        });
      };

      if(subscription.get('gift_type')) {
        subscribe({code: subscription.get('gift_code')}, 'gift_code');
      } else {
        Subscription.purchase(subscription).then(function(result) {
          console.error('purchase_promise_resolved');
          subscribe(result, subscription.get('subscription_amount_plus_trial'));
        }, function() {
          modal.error(i18n.t('purchasing_not_completed', "There was an unexpected problem completing your purchase"));
          console.error('purchase_promise_rejected');
        });
      }
    }
  }
});
