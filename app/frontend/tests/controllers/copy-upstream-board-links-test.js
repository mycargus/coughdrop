import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import EmberObject from '@ember/object';
import startApp from '../helpers/start-app';

describe('CopyUpstreamBoardLinksController', 'controller:copy-upstream-board-links', function() {
  it("should exist", function() {
    expect(this).not.toEqual(null);
    expect(this).not.toEqual(window);
  });
});
// import Ember from 'ember';
// import modal from '../utils/modal';
//
// export default EmberObjectController.extend({
//   needs: 'application',
//   actions: {
//     tweakBoard: function(decision) {
//       modal.close();
//       this.get('controllers.application').send('tweakBoard', decision);
//     },
//     close: function() {
//       modal.close();
//     }
//   }
// });
