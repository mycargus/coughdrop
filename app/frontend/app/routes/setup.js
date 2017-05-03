import Ember from 'ember';
import app_state from '../utils/app_state';

export default Ember.Route.extend({
  setupController: function(controller) {
    app_state.controller.set('setup_footer', true);
    app_state.controller.set('footer_status', null);
    app_state.controller.set('setup_order', controller.order);
    app_state.controller.set('setup_extra_order', controller.extra_order);
    controller.update_on_page_change();
  }
});
