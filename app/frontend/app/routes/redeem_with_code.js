import Ember from 'ember';
import Route from '@ember/routing/route';
import EmberObject from '@ember/object';
import RSVP from 'rsvp';

export default Route.extend({
  controllerName: 'redeem',
  model: function(params) {
    var obj = this.store.findRecord('gift', params.code);
    return obj.then(function(data) {
      return RSVP.resolve(data);
    }, function() {
      return RSVP.resolve(EmberObject.create({invalid: true, code: params.code}));
    });
  },
  setupController: function(controller, model) {
    var _this = this;

    controller.set('model', model);
  }
});
