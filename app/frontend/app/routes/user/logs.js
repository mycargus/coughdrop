import Ember from 'ember';
import Route from '@ember/routing/route';
import i18n from '../../utils/i18n';

export default Route.extend({
  model: function() {
    var user = this.modelFor('user');
    user.set('subroute_name', i18n.t('messages', 'messages'));
    return user;
  },
  resetController: function(controller, isExiting) {
    if(isExiting) {
      controller.reset_params();
    }
  },
  setupController: function(controller, model) {
    controller.set('user', this.modelFor('user'));
    controller.set('model', model);
    controller.send('refresh');
  }
});
