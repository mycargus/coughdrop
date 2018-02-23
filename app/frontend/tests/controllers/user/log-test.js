import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import startApp from '../../helpers/start-app';

describe('UserLogController', 'controller:user-log', function() {
  it("should exist", function() {
    expect(this).not.toEqual(null);
    expect(this).not.toEqual(window);
  });
});
// import Ember from 'ember';
// 
// export default EmberObjectController.extend({
//   title: function() {
//     return "Log Details";
//   }.property('user_name'),
//   needs: 'user',
//   actions: {
//     lam_export: function() {
//       window.open('/api/v1/logs/' + this.get('id') + '/lam?nonce=' + this.get('nonce'));
//     },
//     toggle_notes: function(id, action) {
//       this.get('model').toggle_notes(id);
//       if(action == 'add') {
//         emberRun.later(function() {
//           $("input[data-event_id='" + id + "']").focus().select();
//         }, 200);
//       }
//     },
//     add_note: function(event_id) {
//       var val = $("input[data-event_id='" + event_id + "']").val();
//       if(val) {
//         this.get('model').add_note(event_id, val);
//       }
//       $("input[data-event_id='" + event_id + "']").val("");
//     }
//   }
// });