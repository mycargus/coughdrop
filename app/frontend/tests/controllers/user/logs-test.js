import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import startApp from '../../helpers/start-app';

describe('UserLogsController', 'controller:user-logs', function() {
  it("should exist", function() {
    expect(this).not.toEqual(null);
    expect(this).not.toEqual(window);
  });
});
// import Ember from 'ember';
// import modal from '../../utils/modal';
// 
// export default EmberObjectController.extend({
//   queryParams: ['type'],
//   type: null,
//   title: function() {
//     return "Logs for " + this.get('user_name');
//   }.property('user_name'),
//   needs: 'user',
//   refresh_on_type_change: function() {
//     this.send('refresh');
//   }.observes('type'),
//   messages_only: function() {
//     return this.get('type') == 'note';
//   }.property('type'),
//   all_logs: function() {
//     return !this.get('type') || this.get('type') == 'all';
//   }.property('type'),
//   actions: {
//     recordNote: function(type) {
//       var _this = this;
//       var user = this.get('model');
//       if(type == 'video' && !user.get('premium_enabled')) {
//         return modal.open('premium-required', {action: 'record_video_note'});
//       }
//       modal.open('record-note', {type: type}).then(function() {
//         _this.send('refresh');
//       });
//     },
//     refresh: function() {
//       if(!this.get('id')) { return; }
//       var controller = this;
//       if(this.get('type') == 'all') { this.set('type', null); }
//       var args = {user_id: this.get('id')};
//       if(this.get('type') && this.get('type') != 'all') {
//         args.type = this.get('type');
//       }
//       if(this.get('logs')) {
//         this.set('logs', []);
//       }
//       this.store.find('log', args).then(function(list) {
//         controller.set('logs', list.get('content'));
//         var meta = $.extend({}, list.meta);
//         controller.set('meta', meta);
//         // weird things happen if we try to observe meta.next_url, it stops
//         // updating on subsequent requests.. hence this setter.
//         controller.set('more_available', !!meta.next_url);
// 
//         if(controller.get('type') == 'note' && controller.get('model')) {
//           var user = controller.get('model');
//           var log = controller.get('logs')[0];
//           if(log && log.get('time_id') && user.get('last_message_read') != log.get('time_id')) {
//             // TODO: there's a reloadRecord error happening here without the timeout,
//             // you should probably figure out the root issue
//             emberRun.later(function() {
//               user.set('last_message_read', log.get('time_id'));
//               user.save();
//             }, 1000);
//           }
//         }
//       }, function() { });
//     },
//     more: function() {
//       var _this = this;
//       if(this.get('more_available')) {
//         var meta = this.get('meta');
//         var args = {user_id: this.get('id'), per_page: meta.per_page, offset: (meta.offset + meta.per_page)};
//         if(this.get('type') && this.get('type') != 'all') {
//           args.type = this.get('type');
//         }
//         var find = this.store.find('log', args);
//         find.then(function(list) {
//           _this.set('logs', _this.get('logs').concat(list.get('content')));
//           var meta = $.extend({}, list.meta);
//           _this.set('meta', meta);
//           _this.set('more_available', !!meta.next_url);
//         }, function() { });
//       }
//     },
//     clearLogs: function() {
//       modal.open('confirm-delete-logs', {user: this.get('model')});
//     }
//   }
// });