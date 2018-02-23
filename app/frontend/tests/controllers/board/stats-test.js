import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import EmberObject from '@ember/object';
import startApp from '../../helpers/start-app';

describe('BoardStatsController', 'controller:board-stats', function() {
  it("should exist", function() {
    expect(this).not.toEqual(null);
    expect(this).not.toEqual(window);
  });
});
// import Ember from 'ember';
// import persistence from '../../utils/persistence';
// import app_state from '../../utils/app_state';
// import modal from '../../utils/modal';
//
// export default EmberObjectController.extend({
//   needs: ['board', 'application'],
//   load_charts: function() {
//     var _this = this;
//     _this.set('stats', null);
//     if(persistence.get('online') && app_state.get('currentUser')) {
//       persistence.ajax('/api/v1/boards/' + _this.get('key') + '/stats', {type: 'GET'}).then(function(data) {
//         _this.set('stats', data);
//       }, function() {
//         _this.set('stats', {error: true});
//       });
//     }
//   },
//   actions: {
//     close: function() {
//       modal.close();
//     }
//   }
// });
