import Ember from 'ember';
import Route from '@ember/routing/route';
import i18n from '../../utils/i18n';

export default Route.extend({
  model: function() {
    var user = this.modelFor('user');
    user.set('subroute_name', i18n.t('preferences', 'preferences'));
    return user;
  },
  setupController: function(controller, model) {
    model.set('watch_cookies', true);
    controller.set('model', model);
    controller.set('add_sidebar_board_error', null);
    controller.check_core_words();
    controller.check_voices_available();
    controller.set_auto_sync();
    controller.check_calibration();
    controller.set('status', null);
  }
});
