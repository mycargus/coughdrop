import Ember from 'ember';
import Controller from '@ember/controller';
import { later as runLater } from '@ember/runloop';
import Subscription from '../utils/subscription';
import app_state from '../utils/app_state';
import i18n from '../utils/i18n';
import modal from '../utils/modal';
import persistence from '../utils/persistence';
import progress_tracker from '../utils/progress_tracker';

export default Controller.extend({
  update_classes: Subscription.obs_func.observes.apply(Subscription.obs_func, Subscription.obs_properties),
  subscription: function() {
    var res;
    if(app_state.get('currentUser')) {
      res = Subscription.create({user: app_state.get('currentUser')});
    } else {
      res = Subscription.create();
    }
    res.set('user_type', 'communicator');
    res.set('subscription_type', 'long_term_gift');
    var _this = this;
    runLater(function() {
      _this.update_classes();
    });
    return res;
  }.property('app_state.currentUser'),
  check_valid_amount: function(force) {
    var amount = parseInt(this.get('subscription.subscription_custom_amount'), 10);
    if(amount && (amount < 150 || (amount % 50 !== 0))) {
      if(this.get('custom_amount_error') === undefined && force !== true) {
        var _this = this;
        runLater(function() {
          _this.check_valid_amount(true);
        }, 2000);
      } else {
        this.set('custom_amount_error', true);
      }
    } else {
      if(this.get('custom_amount_error') !== undefined) {
        this.set('custom_amount_error', false);
      }
    }
  }.observes('subscription.subscription_custom_amount'),
  actions: {
    reset: function() {
      this.get('subscription').reset();
      this.set('subscription.user_type', 'communicator');
      this.set('subscription.subscription_type', 'long_term_gift');
    },
    set_subscription: function(amount) {
      this.set('subscription.subscription_amount', amount);
    },
    purchase: function() {
      var subscription = this.get('subscription');
      if(!Subscription.ready || !subscription) {
        modal.error(i18n.t('purchasing_not_read', "There was a problem initializing the purchasing system. Please contact support."));
        return;
      } else if(!subscription.get('valid')) {
        return;
      }
      var _this = this;
      _this.set('purchase_error', null);
      var user = _this.get('model');
      var subscribe = function(token, type) {
        subscription.set('finalizing_purchase', true);
        persistence.ajax('/api/v1/purchase_gift', {
          type: 'POST',
          data: {
            token: token,
            type: type,
            email: _this.get('subscription.email')
          }
        }).then(function(data) {
          progress_tracker.track(data.progress, function(event) {
            if(event.status == 'errored') {
              _this.set('purchase_error', i18n.t('user_subscription_update_failed', "Purchase failed. Please try again or contact support for help."));
              _this.send('reset');
              console.log(event);
            } else if(event.status == 'finished' && event.result && event.result.success === false && event.result.error == 'card_declined') {
              var str = i18n.t('card_declined', "Purchase failed, your card was declined. Please try a different card or contact support for help.");
              if(event.result.decline_code && event.result.decline_code == 'fraudulent') {
                str = i18n.t('card_declined_by_billing', "Purchase failed, our billing system has flagged your card as high-risk. Please try a different card or contact support for help.");
              }
              _this.set('purchase_error', str);
              _this.send('reset');
            } else if(event.status == 'finished') {
              _this.set('subscription.purchase_complete', true);
            }
          });
        }, function() {
          _this.send('reset');
          modal.error(i18n.t('user_subscription_update_failed', "Purchase failed unexpectedly. Please contact support for help."));
        });
      };

      if(subscription.get('subscription_amount') == 'long_term_200' && subscription.get('much_cheaper_offer')) {
        subscription.set('subscription_amount', 'long_term_100');
      }
      Subscription.purchase(subscription).then(function(result) {
        var amount = subscription.get('subscription_amount');
        if(amount == 'long_term_custom') {
          var num = subscription.get('subscription_custom_amount');
          amount = 'long_term_custom_' + num;
        } if(amount == 200) {
        }
        subscribe(result, amount);
      });
    }
  }
});
