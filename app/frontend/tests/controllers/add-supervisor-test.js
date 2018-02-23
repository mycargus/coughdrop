import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import EmberObject from '@ember/object';
import startApp from '../helpers/start-app';

describe('AddSupervisorController', 'controller:add-supervisor', function() {
  it("should exist", function() {
    expect(this).not.toEqual(null);
    expect(this).not.toEqual(window);
  });
});
// import Ember from 'ember';
// import modal from '../utils/modal';
//
// export default EmberObjectController.extend({
//   needs: 'user',
//   actions: {
//     close: function() {
//       modal.close();
//     },
//     add: function() {
//       var controller = this;
//       controller.set('linking', true);
//       var user = this.get('controllers.user').get('model');
//       var type = this.get('edit_permission') ? 'add_edit' : 'add';
//       user.set('supervisor_key', type + "-" + this.get('supervisor_key'));
//       // TODO: does this also update application.currentUser?
//       user.save().then(function() {
//         controller.set('linking', false);
//         modal.close();
//       }, function() {
//         controller.set('linking', false);
//         controller.set('error', true);
//       });
//     }
//   }
// });
