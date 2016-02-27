import Ember from 'ember';
import Subscription from '../utils/subscription';
import app_state from '../utils/app_state';
import i18n from '../utils/i18n';
import modal from '../utils/modal';
import persistence from '../utils/persistence';
import progress_tracker from '../utils/progress_tracker';

export default Ember.Controller.extend({
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
    Ember.run.later(function() {
      _this.update_classes();
    });
    return res;
  }.property('app_state.currentUser'),
  actions: {
    reset: function() {
      this.get('subscription').reset();
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
              modal.error(i18n.t('user_subscription_update_failed', "Subscription failed. Please try again or contact support for help."));
              _this.send('reset');
              console.log(event);
            } else if(event.status == 'finished') {
              _this.set('subscription.purchase_complete', true);
            }
          });
        }, function() {
          _this.send('reset');
          modal.error(i18n.t('user_subscription_update_failed', "Subscription failed unexpectedly. Please contact support for help."));
        });
      };
      
      Subscription.purchase(subscription).then(function(result) {
        var amount = subscription.get('subscription_amount');
        if(amount == 'long_term_custom') {
          var num = subscription.get('subscription_custom_amount');
          amount = 'long_term_custom_' + num;
        }
        subscribe(result, amount);
      });
    }
  }
});