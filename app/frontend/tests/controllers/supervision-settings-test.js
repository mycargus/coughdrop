import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import startApp from '../helpers/start-app';

describe('SupervisionSettingsController', 'controller:supervision-settings', function() {
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
//     remove_supervisor: function(id) {
//       var user = this.get('model');
//       user.set('supervisor_key', "remove_supervisor-" + id);
//       user.save().then(null, function() {
//         alert("sadness!");
//       });
//     },
//     remove_supervisee: function(id) {
//       var user = this.get('model');
//       user.set('supervisor_key', "remove_supervisee-" + id);
//       user.save().then(null, function() {
//         alert("sadness!");
//       });
//     },
//     add_supervisor: function() {
//       modal.open('add-supervisor');
//     }
//   }
// });
