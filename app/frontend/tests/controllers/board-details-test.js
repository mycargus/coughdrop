import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import EmberObject from '@ember/object';
import startApp from '../helpers/start-app';

describe('BoardDetailsController', 'controller:board-details', function() {
  it("should exist", function() {
    expect(this).not.toEqual(null);
    expect(this).not.toEqual(window);
  });
});
// import Ember from 'ember';
// import modal from '../utils/modal';
//
// export default EmberObjectController.extend({
//   needs: 'board',
//   images_with_license: function() {
//     return this.get('local_images_with_license');
//   }.property('buttons', 'grid'),
//   sounds_with_license: function() {
//     return this.get('local_sounds_with_license');
//   }.property('buttons', 'grid'),
//   actions: {
//     close: function() {
//       modal.close();
//     },
//     show_licenses: function() {
//       this.set('showing_licenses', true);
//     }
//   }
// });
