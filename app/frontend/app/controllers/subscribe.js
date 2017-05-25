import modal from '../utils/modal';
import app_state from '../utils/app_state';
import i18n from '../utils/i18n';
import Subscription from '../utils/subscription';

export default modal.ModalController.extend({
  opening: function() {
    if(app_state.get('currentUser')) {
      this.set('model', {
        user: app_state.get('currentUser'),
        subscription: Subscription.create({user: app_state.get('currentUser')})
      });
      Subscription.init();
    } else {
      this.set('error', i18n.t('subscribe_no_user', "No user was found"));
    }
  },
  actions: {
    subscription_skip: function() {
      modal.close();
      this.transitionToRoute('setup');
    },
    subscription_error: function(err) {
      this.set('error', err);
    },
    subscription_success: function(msg) {
      modal.close();
      this.transitionToRoute('setup');
      modal.success(msg);
    }
  }
});
