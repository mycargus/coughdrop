import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import EmberObject from '@ember/object';
import startApp from '../helpers/start-app';

describe('AddAppController', 'controller:add-app', function() {
  it("should exist", function() {
    expect(this).not.toEqual(null);
    expect(this).not.toEqual(window);
  });
});
// export default EmberObjectController.extend({
//   device: function() {
//     return {
//       standalone: navigator.standalone,
//       android: (navigator.userAgent.match(/android/i) && navigator.userAgent.match(/chrome/i)),
//       ios: (navigator.userAgent.match(/mobile/i) && navigator.userAgent.match(/safari/i))
//     };
//   }.property(),
//   actions: {
//     close: function() {
//       modal.close();
//     }
//   }
// });
