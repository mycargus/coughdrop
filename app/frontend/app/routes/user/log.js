import Ember from 'ember';
import Route from '@ember/routing/route';
import i18n from '../../utils/i18n';

export default Route.extend({
  model: function(params) {
    var user = this.modelFor('user');
    user.set('subroute_name', i18n.t('messages', 'messages'));
    return this.store.findRecord('log', params.log_id);
  },
  setupController: function(controller, model) {
    if(!model.get('events')) {
      model.reload();
    }
    controller.set('user', this.modelFor('user'));
    controller.set('model', model);
  }
});
