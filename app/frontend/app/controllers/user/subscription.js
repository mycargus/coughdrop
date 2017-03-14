import Ember from 'ember';
import Subscription from '../../utils/subscription';
import modal from '../../utils/modal';
import i18n from '../../utils/i18n';
import persistence from '../../utils/persistence';
import progress_tracker from '../../utils/progress_tracker';

export default Ember.Controller.extend({
  queryParams: ['code', 'confirmation'],
  code: null,
  confirmation: null,
  actions: {
    subscription_error: function(err) {
      modal.error(err);
    },
    subscription_success: function(msg) {
      modal.success(msg);
      this.get('subscription').reset();
    },
    approve_or_reject_org: function(approve) {
      var user = this.get('model');
      var type = this.get('edit_permission') ? 'add_edit' : 'add';
      var _this = this;
      if(approve) {
        user.set('supervisor_key', "approve-org");
      } else {
        user.set('supervisor_key', "remove_supervisor-org");
      }
      user.save().then(function(user) {
        var sub = Subscription.create({user: user});
        sub.reset();
        _this.set('subscription', sub);
      }, function() { });
    },
    reset: function() {
      this.get('subscription').reset();
    },
    show_options: function() {
      this.set('subscription.show_options', true);
      this.set('subscription.show_cancel', false);
    },
    // "frd" == "for reals, dude". See previous notes on the subject.
    cancel_subscription: function(frd) {
      var _this = this;
      var user = _this.get('model');
      if(frd) {
        this.set('subscription.canceling', true);
        persistence.ajax('/api/v1/users/' + user.get('user_name') + '/subscription', {
          type: 'DELETE'
        }).then(function(data) {
          progress_tracker.track(data.progress, function(event) {
            if(event.status == 'errored') {
              modal.error(i18n.t('user_subscription_cancel_failed', "Subscription cancellation failed. Please try again or contact support for help."));
              console.log(event);
            } else if(event.status == 'finished') {
              modal.success(i18n.t('user_subscription_canceled', "Your subscription has been canceled."));
              user.reload().then(function() {
                _this.send('reset');
              });
            }
          });
        }, function() {
          modal.error(i18n.t('user_subscription_cancel_failed', "Subscription cancellation failed. Please try again or contact support for help."));
        });
      } else {
        this.set('subscription.show_options', true);
        this.set('subscription.show_cancel', true);
      }
    },
    show_expiration_notes: function() {
      this.set('show_expiration_notes', true);
    }
  }
});
