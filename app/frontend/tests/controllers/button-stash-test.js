import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import EmberObject from '@ember/object';
import startApp from '../helpers/start-app';

describe('ButtonStashController', 'controller:button-stash', function() {
  it("should exist", function() {
    expect(this).not.toEqual(null);
    expect(this).not.toEqual(window);
  });
});
// import Ember from 'ember';
// import CoughDrop from '../utils/app';
// import editManager from '../utils/edit_manager';
// import modal from '../utils/modal';
//
// export default EmberObjectController.extend({
//   needs: 'board',
//   actions: {
//     close: function() {
//       modal.close();
//     },
//     pickButton: function(button) {
//       editManager.get_ready_to_apply_stashed_button(button);
//       modal.close(true);
//     }
//   },
//   outer_button_style: function() {
//     return "width: 33%; height: 100px; padding: 5px;";
//   }.property('id'),
//   inner_button_style: function() {
//     var height = 100 - CoughDrop.borderPad;
//     return "height: " + height + "px;";
//   }.property('id'),
//   image_style: function() {
//     var height = 100 - CoughDrop.labelHeight - CoughDrop.boxPad;
//     return "height: " + height + "px;";
//   }.property('id')
// });
