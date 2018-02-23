import Ember from 'ember';
import Route from '@ember/routing/route';
import persistence from '../../utils/persistence';

export default Route.extend({
  setupController: function(controller, model) {
    var _this = this;
    controller.load_goals();
  }
});
