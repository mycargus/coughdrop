import Ember from 'ember';
import i18n from '../../utils/i18n';

export default Ember.Route.extend({
  model: function() {
    var user = this.modelFor('user');
    user.set('subroute_name', i18n.t('preferences', 'preferences'));
    return user;
  },
  setupController: function(controller, model) {
    controller.set('model', model);
    controller.check_core_words();
    controller.check_voices_available();
    controller.set_auto_sync();
  }
});
