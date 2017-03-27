import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import startApp from '../helpers/start-app';

describe('WhichHomeController', 'controller:which-home', function() {
  it("should exist", function() {
    expect(this).not.toEqual(null);
    expect(this).not.toEqual(window);
  });
});
// import modal from '../utils/modal';
// import app_state from '../utils/app_state';
//
// export default modal.ModalController.extend({
//   needs: 'application',
//   actions: {
//     toggleSpeakMode: function(decision) {
//       app_state.toggle_speak_mode(decision);
//     }
//   }
// });
