import Ember from 'ember';
import i18n from '../../utils/i18n';

export default Ember.Route.extend({
  model: function() {
    var model = this.modelFor('user');
    model.set('subroute_name', i18n.t('profile', 'profile'));
    return model;
  },
  setupController: function(controller, model) {
    controller.set('model', model);
    controller.load_integrations();
  }
});
